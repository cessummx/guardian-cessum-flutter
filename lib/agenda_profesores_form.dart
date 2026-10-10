// (23-sep) Formulario de asignación y hoja de alumnos del curso de la Agenda de
// profesores. Es PARTE de agenda_profesores_screen.dart: los imports están allá.
part of 'agenda_profesores_screen.dart';

// ===========================================================================
// (28-sep) FASE 0 — REGLAS INSTITUCIONALES: FUENTE ÚNICA
// ---------------------------------------------------------------------------
// Motivo: el mismo día se encontró un bug real (Maestría en Educación 26-3
// sabatino salía preseleccionada a 10 semanas en vez de 4) causado porque la
// regla de "cuántas semanas dura una materia" vivía repartida en varias
// funciones, cada una con su propio orden de condiciones. Aquí queda en UN
// solo lugar: _reglaDe(programa, grupoTipo). Los getters _semanasDefault,
// _tieneHorarioFijo, _bloquesHorario y _horaPredeterminada (más abajo, en la
// clase del formulario) solo LEEN el resultado — ya no deciden nada.
//
// Para dar de alta un programa con reglas propias: se agrega un caso AQUÍ,
// no se reparte por el archivo. El comportamiento de cada rama está probado
// contra el código anterior, materia por materia; no se cambió ningún valor,
// solo dónde vive la decisión.
// ===========================================================================

/// Modalidad del grupo, deducida de "grupo + tipo de sesiones" (la misma
/// cadena que ya se arma en todo el formulario). Antes cada función volvía a
/// comparar .contains('mixt') / .contains('sabat') por su cuenta.
enum _Modalidad { mixta, sabatino, entreSemana }

_Modalidad _modalidadDe(String grupoTipo) {
  final g = grupoTipo.toLowerCase();
  if (g.contains('mixt')) return _Modalidad.mixta;
  if (g.contains('sabat')) return _Modalidad.sabatino;
  return _Modalidad.entreSemana;
}

// (15-sep) BLOQUES DE LICENCIATURA. El sábado va de 8:00 a 16:00 en siete
// bloques de una hora, con receso de 30 min a las 12:00 y de 15 min a las
// 14:45. No se escriben a mano: se eligen, y así dos materias no acaban con
// horas que no corresponden a ningún bloque.
const List<String> _bloquesLic = [
  '08:00 - 09:00',
  '09:00 - 10:00',
  '10:00 - 11:00',
  '11:00 - 12:00',
  '12:30 - 13:30',
  '13:45 - 14:45',
  '15:00 - 16:00',
];

// Sabatinos de posgrado: dos materias por sábado, en estos dos bloques.
const List<String> _bloquesSabPos = ['10:00 - 11:30', '11:30 - 13:00'];

/// Lo que la institución fija para una materia, antes de que nadie la toque:
/// cuántas semanas dura por omisión, si tiene horario fijo, qué bloques de
/// hora ofrecer y cuál va preseleccionada. Inmutable: se calcula una vez y
/// se consulta, nunca se decide dos veces.
class _ReglaAsignacion {
  final int semanas;
  final bool horarioFijo;
  final List<String> bloques;
  final String horaPredeterminada;
  const _ReglaAsignacion({
    required this.semanas,
    required this.horarioFijo,
    required this.bloques,
    required this.horaPredeterminada,
  });
}

/// (2-oct-2026) Un aviso sobre las fechas de una asignación. «grave» es lo que
/// casi seguro es un error; lo demás es «revísalo» y puede ser intencional.
class _AvisoFecha {
  final String texto;
  final bool grave;
  const _AvisoFecha(this.texto, this.grave);
}

/// LA REGLA. programaCrudo y grupoTipoCrudo llegan tal cual los escribió
/// quien captura (con o sin acentos, con o sin mayúsculas); aquí se
/// normalizan una sola vez con _normaPrograma (ya existe arriba, en
/// agenda_profesores_screen.dart — misma librería, se reutiliza en vez de
/// volver a escribir el reemplazo de acentos).
_ReglaAsignacion _reglaDe(String programaCrudo, String grupoTipoCrudo) {
  final pn = _normaPrograma(programaCrudo);
  final mod = _modalidadDe(grupoTipoCrudo);

  // Licenciatura: cuatrimestre completo, las 7 materias corren en PARALELO
  // (no se encadenan), sábados en los 7 bloques fijos de una hora. La
  // modalidad del grupo no cambia nada aquí: el programa manda.
  if (pn.contains('licenciatura')) {
    return const _ReglaAsignacion(
      semanas: 14,
      horarioFijo: false,
      bloques: _bloquesLic,
      horaPredeterminada: '',
    );
  }

  // Maestría en Educación: la ÚNICA con horario institucional fijo.
  // OJO — comparación EXACTA (==), no .contains(): con .contains(),
  // "Maestría en Educación Inclusiva" también entraría aquí, y esa NO
  // tiene horario fijo ni las 4 semanas (va a 5, como el resto de posgrado).
  if (pn == 'maestria en educacion') {
    if (mod == _Modalidad.mixta) {
      return const _ReglaAsignacion(
        semanas: 4,
        horarioFijo: true,
        bloques: [],
        horaPredeterminada: '',
      );
    }
    if (mod == _Modalidad.sabatino) {
      return const _ReglaAsignacion(
        semanas: 4,
        horarioFijo: true,
        bloques: ['10:00 - 12:00'],
        horaPredeterminada: '10:00-12:00',
      );
    }
    return const _ReglaAsignacion(
      semanas: 4,
      horarioFijo: true,
      bloques: ['19:30 - 21:00'],
      horaPredeterminada: '19:30-21:00',
    );
  }

  // Resto de posgrado (incluida la Inclusiva): sin horario fijo — lo acuerda
  // el docente con su grupo. Sabatino tiene los 2 bloques cerrados de
  // posgrado y dura 10 semanas; mixta y entre semana quedan libres, 5.
  if (mod == _Modalidad.sabatino) {
    return const _ReglaAsignacion(
      semanas: 10,
      horarioFijo: false,
      bloques: _bloquesSabPos,
      horaPredeterminada: '',
    );
  }
  return const _ReglaAsignacion(
    semanas: 5,
    horarioFijo: false,
    bloques: [],
    horaPredeterminada: '',
  );
}

class _AsignacionForm extends StatefulWidget {
  final Map<String, Map<String, List<String>>> catalogo;
  // Generaciones egresadas como llaves "programa||generación" normalizadas.
  final Set<String> egresadas;
  final Map<String, dynamic>? existente;
  final String? presetPrograma;
  final String? presetGeneracion;
  final String? presetGrupo;
  // Asignaciones existentes (para calcular el rango sugerido de fechas).
  final List<Map<String, dynamic>> asignaciones;
  const _AsignacionForm({
    required this.catalogo,
    required this.egresadas,
    this.existente,
    this.presetPrograma,
    this.presetGeneracion,
    this.presetGrupo,
    this.asignaciones = const [],
  });

  @override
  State<_AsignacionForm> createState() => _AsignacionFormState();
}

class _AsignacionFormState extends State<_AsignacionForm> {
  String? _programa;
  String? _generacion;
  String? _grupo;
  String? _periodo;
  final _cProg = TextEditingController();
  final _cGen = TextEditingController();
  final _cGrupo = TextEditingController();

  final _cMateria = TextEditingController();
  final _cClave = TextEditingController();
  // Bloque conjunto (solo Mixta, excepcional): materias que se imparten juntas
  // con una sola invitación, un pago y una calificación. La materia del
  // formulario es la 'principal'; aquí se acumulan las adicionales.
  final List<Map<String, String>> _bloqueMaterias = [];
  // Selección múltiple desde el panel de Avance (solo Mixta): se marcan varias
  // materias y se agendan juntas con "Agendar juntas". Llave = clave o nombre.
  final Map<String, Map<String, String>> _selAvance = {};
  // Juntar grupos: la MISMA materia+profesor se imparte a varios grupos a la
  // vez (una invitación, pero al calificar cada grupo lleva su acta). Aquí se
  // acumulan los grupos ADICIONALES al del formulario. {programa,generacion,grupo}
  final List<Map<String, String>> _gruposJuntos = [];
  final _cGrupoExtra = TextEditingController();
  final _cGenExtra = TextEditingController();

  void _agregarGrupoJunto() {
    final grp = _cGrupoExtra.text.trim();
    final gen = _cGenExtra.text.trim().isEmpty
        ? _valGen()
        : _cGenExtra.text.trim();
    if (grp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Escribe el grupo a juntar (ej. 1 - mixta).')));
      return;
    }
    final llave = '$gen|$grp'.toLowerCase();
    // Evitar duplicar el grupo del formulario o uno ya agregado.
    final propia = '${_valGen()}|${_valGrupo()}'.toLowerCase();
    if (llave == propia ||
        _gruposJuntos.any((e) =>
            '${e['generacion']}|${e['grupo']}'.toLowerCase() == llave)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ese grupo ya está incluido.')));
      return;
    }
    setState(() {
      _gruposJuntos.add({
        'programa': _valProg(),
        'generacion': gen,
        'grupo': grp,
      });
      _cGrupoExtra.clear();
      _cGenExtra.clear();
    });
  }

  void _quitarGrupoJunto(int i) {
    setState(() => _gruposJuntos.removeAt(i));
  }

  String _llaveMat(Map<String, dynamic> m) {
    final clv = (m['clave'] ?? '').toString().trim();
    final nom = (m['denominacion'] ?? '').toString().trim();
    return clv.isNotEmpty ? clv : nom.toLowerCase();
  }
  final _cHora = TextEditingController();
  final _cCiclo = TextEditingController();
  final _cDocente = TextEditingController();
  final _cCorreo = TextEditingController();

  // Padrón de profesores para el desplegable de maestro.
  List<Map<String, String>> _profes = [];
  bool _maestroManual = false;

  /* (22-sep) MAESTROS SUGERIDOS PARA LA MATERIA. Al escribir la materia, el
     Guardián propone primero a quienes YA la impartieron —con cuántas veces,
     dónde y cuándo— y luego a quienes tienen perfil acorde por su semblanza
     y escolaridad. Un toque los elige; el desplegable sigue ahí para
     cualquier otro. */
  Map<String, dynamic>? _sugeridos;
  // (29-sep) Sugerencia con IA: una sola recomendación concreta (docente,
  // día, hora y por qué), no solo nombres sueltos como los chips de abajo.
  Map<String, dynamic>? _sugerenciaIa;
  List<Map<String, dynamic>> _alternativasIa = [];
  bool _cargandoIa = false;
  String? _errorIa;
  String _sugMateria = '';
  // (30-sep) Orden curricular: si la materia elegida tiene, delante en el
  // plan, materias de un periodo anterior que este grupo aún no tiene
  // registradas — se avisa AQUÍ, en cuanto se elige, no hasta que el
  // guardado se rechace.
  List<Map<String, dynamic>>? _ordenFaltantes;
  String _ordenMateriaVerificada = '';
  // (2-oct) Historial por calificaciones: materias que el grupo ya cursó según sus
  // actas pero que no tienen fila en la agenda. Solo informativo; no se escribe nada.
  List<Map<String, dynamic>> _histCalif = [];
  String _histCalifClave = '';
  bool _sugCargando = false;
  String? _maestroSelCorreo;
  final Set<String> _ocupados = {};
  // Buscador del selector de maestro: la planta docente pasa de 30 nombres.
  final _filtroProfes = TextEditingController();
  final Map<String, String> _conflicto = {};
  bool _dispFiltrado = false;
  // (29-sep) BLOQUES DEL SÁBADO OCUPADOS: antes había que adivinar cuál de
  // los bloques (10:00-11:30 / 11:30-13:00) ya tenía clase del grupo o del
  // maestro elegido — el choque solo aparecía hasta intentar guardar. Ahora
  // se consulta antes, igual que _ocupados para el dropdown de maestro: el
  // bloque ocupado NO se esconde, se marca con quién/qué lo tiene.
  final Map<String, String> _bloqueOcupadoPor = {}; // hora -> correo/nombre de quién
  final Map<String, String> _bloqueOcupaQue = {};   // hora -> "Materia · (hora)"
  final Map<String, String> _bloqueOcupaHasta = {}; // hora -> "dd/MM/yyyy" de término
  List<Map<String, dynamic>> _bloqueAnterior = [];  // el bloque que ya terminó, para dar contexto
  String _bloqueAnteriorInicio = '';   // (2-oct) rango del bloque anterior, solo día: dd/MM/aaaa
  String _bloqueAnteriorTermino = '';
  bool _bloquesVerificados = false;
  bool _bloquesFallo = false;
  // (29-sep) HORARIO ACTUAL DEL MAESTRO ELEGIDO: al seleccionarlo en la
  // asignación directa, se muestra de inmediato lo que ya está dando —
  // agrupado por día — para decidir a qué hora ponerlo sin tener que ir a
  // buscarlo aparte. Guiado, no un formulario plano.
  List<Map<String, dynamic>> _horarioMaestro = [];
  String _horarioMaestroNombre = '';
  bool _horarioMaestroCargando = false;
  bool _horarioMaestroFallo = false;
  final _cInicio = TextEditingController();
  final _cTermino = TextEditingController();
  final _cNotas = TextEditingController();
  final _cLlamada = TextEditingController();
  final _cAula = TextEditingController();

  String? _tipo;
  final _cTipo = TextEditingController();
  String? _dia;
  bool _activa = true;
  bool _directo = false;
  // Modo PROSPECTIVO: agendar el siguiente periodo (Mixta) o la siguiente
  // materia (No escolarizada) a futuro. Queda "Programada a futuro" (inactiva),
  // separada de lo actual. El sistema sugiere materia + docente (prioriza a
  // quien ya la impartió), y el admin puede modificar.
  bool _prospectivo = false;
  bool _cargandoSugerencias = false;
  List<Map<String, dynamic>> _materiasSugeridas = [];
  bool _guardando = false;
  // Por defecto se OCULTAN las generaciones egresadas al asignar materias.
  // Este interruptor las vuelve a mostrar cuando hace falta verlas.
  bool _mostrarEgresados = false;

  // ----- Panel de avance del plan (módulo de programación) -----
  bool _avanceCargando = false;
  String? _avanceError;
  Map<String, dynamic>? _avanceData;
  String _avanceKey = '';

  bool _esEgresada(String? gen) {
    if (gen == null || gen == _kOtro) return false;
    final prog = _programa;
    if (prog == null || prog == _kOtro) return false;
    return widget.egresadas
        .contains(_AgendaProfesoresScreenState._keyGen(prog, gen));
  }

  /* (22-sep) TIPO DE SESIONES SIN AMBIGÜEDAD.
     Las opciones mezclaban dos cosas —qué días y cómo se imparte— al mismo
     nivel: una materia sabatina en línea era a la vez «Sabatino» y
     «Virtual», y no había respuesta correcta. «Virtual» no distinguía nada
     (el Guardián solo mira si es mixta o sabatina) y se quitó. Los valores
     guardados no cambian: cambia cómo se explican. */
  final List<String> _tipos = const ['Sabatino', 'Entre semana', 'Mixto'];

  /* (22-sep, 2.ª vuelta) EL TIPO LO DICE EL GRUPO.
     Los grupos ya traen cómo se imparten en su nombre —«1 - entre semana»,
     «2 - sabatino», «1 - mixta»—, así que preguntarlo otra vez solo abría la
     puerta a contradecirlo. Y las etiquetas no correspondían a la realidad:
     todo lo no escolarizado es en línea, y la licenciatura es mixta PERO va
     los sábados, presencial, así que «Mixto» y «Sabatino» eran las dos a la
     vez. Ahora se toma del grupo y se dice cómo se imparte de verdad. Los
     valores guardados no cambian (Entre semana / Sabatino / Mixto): pagos,
     Meet y constancias siguen leyendo lo mismo. */
  bool _tipoManual = false;

  // _esLicenciatura ya existe más abajo en esta misma clase; se reutiliza.
  // (28-sep, Fase 1) _esMEduProg comparaba contra el texto CON ACENTO
  // ('maestría en educación') sin normalizar primero: si el programa llegaba
  // sin acentos (el campo «Otro», o un dato del servidor con otra
  // codificación), esta función decía que NO era Maestría en Educación y la
  // pantalla mostraba la explicación del sabatino GENÉRICO («bloque de
  // 10:00 a 11:30 o de 11:30 a 13:00») en vez de la fija («10:00 a 12:00»).
  // Ahora es la misma _tieneHorarioFijo de la Fase 0: una sola decisión, no
  // dos que puedan desacordarse.
  bool get _esMEduProg => _tieneHorarioFijo;

  /// Tipo que corresponde al grupo elegido, o null si el grupo no lo dice.
  String? _tipoDelGrupo() {
    final g = _valGrupo().toLowerCase();
    if (g.contains('mixt')) return 'Mixto';
    if (g.contains('sabat')) return 'Sabatino';
    if (g.contains('entre') || g.contains('semana')) return 'Entre semana';
    if (_esLicenciatura) return 'Sabatino';
    return null;
  }

  String _tituloTipo(String v) {
    if (v == 'Mixto') return 'Presencial intensivo';
    if (v == 'Sabatino') {
      return _esLicenciatura ? 'Presencial, los sábados' : 'En línea, los sábados';
    }
    if (v == 'Entre semana') return 'En línea, entre semana';
    return v;
  }

  String _detalleTipo(String v) {
    if (v == 'Mixto') return 'Periodo vacacional, días seguidos de 8:00 a 13:00';
    if (v == 'Sabatino') {
      if (_esLicenciatura) return 'Bloques del sábado de 8:00 a 16:00';
      return _esMEduProg
          ? 'Sábado de 10:00 a 12:00'
          : 'Sábado, bloque de 10:00 a 11:30 o de 11:30 a 13:00';
    }
    if (v == 'Entre semana') {
      return _esMEduProg
          ? 'Viernes de 19:30 a 21:00'
          : 'Una sesión semanal de una hora; el día lo acuerda el docente';
    }
    return '';
  }

  IconData _iconoTipo(String v) {
    if (v == 'Mixto') return Icons.meeting_room_outlined;
    if (v == 'Sabatino' && _esLicenciatura) return Icons.school_outlined;
    return Icons.videocam_outlined;
  }
  final List<String> _dias = const [
    'Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'
  ];

  // (15-sep) PRELLENADO SEGÚN EL PROGRAMA Y EL GRUPO.
  // Hasta ahora había que adivinar qué poner en «Tipo de sesiones» y en
  // «Día», aunque la institución ya los tiene definidos por programa. Se
  // sugieren al elegir programa o grupo, y quien captura puede cambiarlos:
  // es una sugerencia, no un candado.
  //
  // La HORA es distinta y por eso no se sugiere en todos: solo la
  // Licenciatura y la Maestría en Educación tienen horario institucional.
  // En los demás programas lo acuerda el docente con su grupo, así que
  // rellenarla sería inventar un dato que la institución no fijó —y ya
  // pasó en agosto: una docente recibió una invitación con un horario que
  // nadie había acordado.
  void _sugerirPorPrograma() {
    final prog = (_programa == _kOtro ? _cProg.text : (_programa ?? ''))
        .toLowerCase();
    final grupo = (_grupo == _kOtro ? _cGrupo.text : (_grupo ?? ''))
        .toLowerCase();
    if (prog.isEmpty) return;

    // (28-sep, Fase 1) esMEdu comparaba contra el texto CON ACENTO sin
    // normalizar: un programa sin acentos nunca activaba la hora fija de
    // Maestría en Educación al sugerir. _normaPrograma (arriba, en
    // agenda_profesores_screen.dart) es la misma que usa _reglaDe (Fase 0):
    // una sola forma de comparar nombres de programa en todo el archivo.
    final pnorm = _normaPrograma(prog);
    final esLic = pnorm.contains('licenciatura');
    final esMEdu = pnorm == 'maestria en educacion';
    // Tipo de sesiones: lo dice el GRUPO (22-sep). Solo se respeta otro
    // valor si alguien lo cambió a mano para un caso excepcional.
    if (!_tipoManual && grupo.isNotEmpty) {
      final t = _tipoDelGrupo();
      if (t != null) _tipo = t;
    }

    // Día. La Mixta no lleva día: es un bloque de días seguidos. La sabatina
    // es en sábado; la de entre semana no puede quedar en fin de semana.
    if (_tipo == 'Mixto') {
      _dia = null;
    } else if (_tipo == 'Sabatino') {
      _dia = 'Sábado';
    } else if (_tipo == 'Entre semana' && (_dia == 'Sábado' || _dia == 'Domingo')) {
      _dia = null;
    }

    // Hora, solo donde hay horario institucional.
    if (_cHora.text.trim().isEmpty) {
      if (esLic) {
        // El horario del grupo es de 8:00 a 16:00; la hora exacta de cada
        // materia la fija el horario del cuatrimestre, así que no se
        // inventa una: se deja al capturista.
      } else if (esMEdu && _tipo == 'Entre semana') {
        _cHora.text = '19:30 - 21:00';
      } else if (esMEdu && _tipo == 'Sabatino') {
        _cHora.text = '10:00 - 12:00';
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _cHora.addListener(_onHoraCambio);
    final e = widget.existente;
    if (e != null) {
      _setSel(e['programa']?.toString(), e['generacion']?.toString(),
          e['grupo']?.toString());
      _cMateria.text = (e['materia'] ?? '').toString();
      _cClave.text = (e['clave'] ?? '').toString();
      _cHora.text = (e['hora'] ?? '').toString();
      _cCiclo.text = (e['ciclo'] ?? '').toString();
      _cDocente.text = (e['docente'] ?? '').toString();
      _cCorreo.text = (e['correo'] ?? '').toString();
      _cInicio.text = (e['inicio'] ?? '').toString();
      _cTermino.text = (e['termino'] ?? '').toString();
      _cNotas.text = (e['notas'] ?? '').toString();
      _cLlamada.text = (e['linkLlamada'] ?? '').toString();
      _cAula.text = (e['linkAula'] ?? '').toString();
      var t = (e['tipoSesiones'] ?? '').toString();
      // (22-sep) Las que se guardaron como «Virtual» se abren con el tipo
      // que les toca según su día o su grupo, en vez de caer en «Otro».
      if (t.trim().toLowerCase() == 'virtual') {
        final dv = (e['dia'] ?? '').toString().toLowerCase();
        final gv = (e['grupo'] ?? '').toString().toLowerCase();
        if (gv.contains('mixt')) {
          t = 'Mixto';
        } else if (dv.startsWith('s') || gv.contains('sabat')) {
          t = 'Sabatino';
        } else if (dv.isNotEmpty || gv.contains('semana')) {
          t = 'Entre semana';
        }
      }
      if (t.isEmpty) {
        _tipo = null;
      } else if (_tipos.contains(t)) {
        _tipo = t;
      } else {
        _tipo = _kOtro;
        _cTipo.text = t;
      }
      final d = (e['dia'] ?? '').toString();
      _dia = _dias.contains(d) ? d : null;
      _activa = (e['activa'] ?? 'SI').toString().toUpperCase() != 'NO';
      // (22-sep) Si lo guardado contradice al grupo, fue a mano: se respeta
      // y se ofrece volver al del grupo. Si estaba vacío, se toma del grupo.
      final delGrupo = _tipoDelGrupo();
      if (_tipo == null && delGrupo != null) {
        _tipo = delGrupo;
      } else if (_tipo == _kOtro || (delGrupo != null && _tipo != delGrupo)) {
        _tipoManual = true;
      }
    } else {
      _setSel(widget.presetPrograma, widget.presetGeneracion,
          widget.presetGrupo);
    }
    // Si la asignación que se abre ya pertenece a una generación egresada,
    // se enciende el interruptor para que su generación siga visible y el
    // formulario no se quede sin opción seleccionada.
    if (_esEgresada(_generacion)) _mostrarEgresados = true;
    _cargarProfes();
    // Carga el avance del grupo si ya hay programa+grupo (p. ej. al editar).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeCargarAvance();
      // (23-sep) Asignación nueva con programa y grupo: llega con propuesta.
      if (mounted && widget.existente == null) _armarPropuesta();
    });
  }

  // Decide si el valor cae en el catálogo (dropdown) o es "Otro" (texto).
  void _setSel(String? prog, String? gen, String? grupo) {
    final progs = widget.catalogo.keys.toList();
    if (prog != null && prog.isNotEmpty) {
      // Coincidencia tolerante a acentos/espacios: si el programa guardado es una
      // variante (p. ej. sin acentos), lo mapeamos a su nombre del catálogo.
      final canon = progs.firstWhere(
        (k) => _normaPrograma(k) == _normaPrograma(prog),
        orElse: () => '',
      );
      if (canon.isNotEmpty) {
        _programa = canon;
      } else {
        _programa = _kOtro;
        _cProg.text = prog;
      }
    }
    final gensMap = (_programa != null && _programa != _kOtro)
        ? (widget.catalogo[_programa] ?? {})
        : {};
    if (gen != null && gen.isNotEmpty) {
      if (gensMap.containsKey(gen)) {
        _generacion = gen;
      } else {
        _generacion = _kOtro;
        _cGen.text = gen;
      }
    }
    final grupos = (_programa != null &&
            _programa != _kOtro &&
            _generacion != null &&
            _generacion != _kOtro)
        ? ((widget.catalogo[_programa]?[_generacion]) ?? <String>[])
        : <String>[];
    if (grupo != null && grupo.isNotEmpty) {
      if (grupos.contains(grupo)) {
        _grupo = grupo;
      } else {
        // (jul-2026) Etiqueta corta/larga: empatar por clave normalizada
        // ("1" selecciona "1 - entre semana" si esa es la del catálogo).
        String? porClave;
        for (final g in grupos) {
          if (_claveGrupo(g) == _claveGrupo(grupo)) { porClave = g; break; }
        }
        if (porClave != null) {
          _grupo = porClave;
        } else {
          _grupo = _kOtro;
          _cGrupo.text = grupo;
        }
      }
    }
  }

  @override
  void dispose() {
    for (final c in [
      _cProg, _cGen, _cGrupo, _cMateria, _cClave, _cHora, _cCiclo,
      _cDocente, _cCorreo, _cInicio, _cTermino, _cNotas, _cLlamada,
      _cAula, _cTipo
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ============ PANEL DE AVANCE DEL PLAN (ruta avance_plan_grupo) ============

  // Decide si conviene (re)cargar el avance según la selección actual.
  void _maybeCargarAvance() {
    final prog = _valProg();
    final grupo = _valGrupo();
    if (prog.isEmpty || grupo.isEmpty) {
      setState(() {
        _avanceData = null;
        _avanceError = null;
        _avanceKey = '';
        _avanceCargando = false;
      });
      return;
    }
    final key = '$prog|${_valGen()}|$grupo';
    if (key == _avanceKey && (_avanceCargando || _avanceData != null)) return;
    _cargarAvance(key);
  }

  Future<void> _cargarAvance(String key) async {
    setState(() {
      _avanceCargando = true;
      _avanceError = null;
      _avanceData = null;
      _avanceKey = key;
    });
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'avance_plan_grupo',
        'programa': _valProg(),
        'generacion': _valGen(),
        'grupo': _valGrupo(),
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 180));
      if (!mounted || key != _avanceKey) return;
      final r = leerRespuesta(resp, accion: 'avance_plan_grupo');
      if (!r.ok) {
        setState(() {
          _avanceCargando = false;
          _avanceError = r.mensaje;
        });
        return;
      }
      setState(() {
        _avanceCargando = false;
        _avanceData = r.datos;
      });
    } catch (e, s) {
      // (28-sep, Fase 3) Solo cae aquí un fallo de RED: la respuesta, si
      // llegó, ya la interpretó leerRespuesta arriba.
      ErrorReporter.reportar(e, s, pantallaForzada: 'agenda:avance_plan_grupo');
      if (!mounted || key != _avanceKey) return;
      setState(() {
        _avanceCargando = false;
        _avanceError = 'No se pudo cargar el avance del grupo: revise su conexión.';
      });
    }
  }

  // UI de "Juntar grupos": la misma materia+profesor a varios grupos. Azul,
  // para distinguirlo del bloque de materias (morado).
  Widget _gruposJuntosUI() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3FB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFAECBE8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.groups, size: 18, color: Color(0xFF1565C0)),
              SizedBox(width: 6),
              Expanded(
                child: Text('Juntar grupos (misma materia y profesor)',
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          Text(
            'Opcional. La materia y el profesor del formulario se agendan también '
            'a los grupos que agregues aquí, con UNA sola invitación. Al calificar, '
            'cada grupo lleva su acta por separado.',
            style: TextStyle(fontSize: 11, color: cessumMuted(context)),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                child: TextField(
                  controller: _cGenExtra,
                  decoration: const InputDecoration(
                    labelText: 'Gen.',
                    hintText: '26-1',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _cGrupoExtra,
                  decoration: const InputDecoration(
                    labelText: 'Grupo a juntar',
                    hintText: '1 - mixta',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: _agregarGrupoJunto,
                icon: const Icon(Icons.add_circle, color: Color(0xFF1565C0)),
                tooltip: 'Agregar grupo',
              ),
            ],
          ),
          if (_gruposJuntos.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Grupos incluidos (además del principal de arriba):',
                style: TextStyle(fontSize: 11, color: cessumMuted(context))),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (var i = 0; i < _gruposJuntos.length; i++)
                  Chip(
                    label: Text(
                        '${_gruposJuntos[i]['generacion']} · ${_gruposJuntos[i]['grupo']}',
                        style: const TextStyle(fontSize: 11.5)),
                    onDeleted: () => _quitarGrupoJunto(i),
                    deleteIcon: const Icon(Icons.close, size: 14),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // UI del bloque conjunto (solo Mixta): botón para agregar la materia actual
  // al bloque y chips con las materias ya agregadas.
  Widget _bloqueConjuntoUI() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F0FA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFC9BCE8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.layers, size: 18, color: Color(0xFF6A4FB0)),
              const SizedBox(width: 6),
              const Expanded(
                child: Text('Impartir varias materias juntas (excepcional)',
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
              TextButton.icon(
                onPressed: _agregarAlBloque,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Agregar', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(foregroundColor: const Color(0xFF6A4FB0)),
              ),
            ],
          ),
          if (_bloqueMaterias.isEmpty)
            Text(
              'Opcional. Carga una materia arriba y toca "Agregar" para sumarla al bloque; luego elige la principal. Todas llevarán una sola calificación y un solo pago.',
              style: TextStyle(fontSize: 11, color: cessumMuted(context)),
            )
          else ...[
            Text('En el bloque (además de la materia principal de arriba):',
                style: TextStyle(fontSize: 11, color: cessumMuted(context))),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (var i = 0; i < _bloqueMaterias.length; i++)
                  Chip(
                    label: Text(_bloqueMaterias[i]['materia'] ?? '',
                        style: const TextStyle(fontSize: 11.5)),
                    onDeleted: () => _quitarDelBloque(i),
                    deleteIcon: const Icon(Icons.close, size: 14),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // Agrega la materia actualmente cargada al BLOQUE conjunto (Mixta) y limpia
  // el campo para elegir otra. La primera materia queda como principal.
  void _agregarAlBloque() {
    final mat = _cMateria.text.trim();
    final clv = _cClave.text.trim();
    if (mat.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Primero carga una materia del plan.')));
      return;
    }
    // Evitar duplicados.
    if (_bloqueMaterias.any((e) => (e['materia'] ?? '').toLowerCase() == mat.toLowerCase())) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Esa materia ya está en el bloque.')));
      return;
    }
    setState(() {
      _bloqueMaterias.add({'materia': mat, 'clave': clv});
      _cMateria.clear();
      _cClave.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Agregada al bloque: $mat. Ahora elige la siguiente.'),
      duration: const Duration(seconds: 2),
    ));
  }

  void _quitarDelBloque(int i) {
    setState(() => _bloqueMaterias.removeAt(i));
  }

  // Carga una materia sugerida en los campos del formulario.
  void _aplicarMateria(Map<String, dynamic> m, String periodo) {
    setState(() {
      _cMateria.text = (m['denominacion'] ?? '').toString();
      _cClave.text = (m['clave'] ?? '').toString();
      if (periodo.isNotEmpty) _cCiclo.text = periodo;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Materia cargada: ${m['denominacion']}'),
      duration: const Duration(seconds: 2),
    ));
  }

  Widget _panelAvance() {
    final prog = _valProg();
    final grupo = _valGrupo();
    if (prog.isEmpty || grupo.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(top: 14),
        child: Text(
          'Elige programa, generación y grupo para ver el avance del plan.',
          style: TextStyle(fontSize: 12, color: cessumFaint(context)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFBF7EF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cessumGold.withOpacity(0.45)),
        ),
        padding: const EdgeInsets.all(12),
        child: _avanceCargando
            ? Row(children: const [
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: cessumGold)),
                SizedBox(width: 10),
                Text('Cargando avance del grupo…',
                    style: TextStyle(fontSize: 13)),
              ])
            : _avanceError != null
                ? Row(children: [
                    Icon(Icons.info_outline,
                        size: 18, color: cessumFaint(context)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(_avanceError!,
                            style: TextStyle(
                                fontSize: 12, color: cessumMuted(context)))),
                  ])
                : _avanceContenido(),
      ),
    );
  }

  Widget _avanceContenido() {
    final data = _avanceData!;
    final resumen = Map<String, dynamic>.from(data['resumen'] ?? {});
    final aviso = (data['aviso'] ?? '').toString();
    final cicloActual = (data['cicloActual'] ?? '').toString();
    final cicloSig = (data['cicloSiguiente'] ?? '').toString();
    final mismo = (data['sugeridasMismoCiclo'] as List<dynamic>? ?? []);
    final sig = (data['sugeridasSiguiente'] as List<dynamic>? ?? []);
    // (2-oct) Materias de periodos ANTERIORES al actual que al grupo aún le faltan.
    final atrasadas = (data['sugeridasAtrasadas'] as List<dynamic>? ?? []);
    final materias = (data['materias'] as List<dynamic>? ?? []);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: const [
          Icon(Icons.timeline, size: 18, color: cessumRed),
          SizedBox(width: 8),
          Expanded(
              child: Text('Avance del grupo',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: cessumRed))),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          _chipResumen('Cursadas', resumen['cursadas'], const Color(0xFF1E7D32)),
          _chipResumen('En curso', resumen['enCurso'], cessumGold),
          _chipResumen('Pendientes', resumen['pendientes'], cessumMuted(context)),
          _chipResumen('Total', resumen['total'], cessumFaint(context)),
        ]),
        if (aviso.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(aviso,
                style: TextStyle(fontSize: 12, color: cessumMuted(context))),
          ),
        if (atrasadas.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(children: const [
            Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFFB7791F)),
            SizedBox(width: 6),
            Expanded(
              child: Text('Faltan de periodos anteriores (conviene agendarlas primero)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFB7791F))),
            ),
          ]),
          const SizedBox(height: 6),
          Wrap(
              spacing: 6,
              runSpacing: 6,
              children: atrasadas.map<Widget>((m) {
                final mm = Map<String, dynamic>.from(m as Map);
                return _chipMateria(mm, '${mm['periodo'] ?? ''}', const Color(0xFFB7791F));
              }).toList()),
        ],
        if (mismo.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
              'Agendar de este ciclo${cicloActual.isNotEmpty ? " · $cicloActual" : ""}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
              spacing: 6,
              runSpacing: 6,
              children: mismo.map<Widget>((m) {
                final mm = Map<String, dynamic>.from(m as Map);
                return _chipMateria(mm, cicloActual, cessumRed);
              }).toList()),
        ],
        if (sig.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
              'Del siguiente ciclo${cicloSig.isNotEmpty ? " · $cicloSig" : ""}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Wrap(
              spacing: 6,
              runSpacing: 6,
              children: sig.map<Widget>((m) {
                final mm = Map<String, dynamic>.from(m as Map);
                return _chipMateria(mm, cicloSig, cessumGold);
              }).toList()),
        ],
        _barraAgendarJuntas(),
        if (materias.isNotEmpty)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              title: const Text('Ver plan completo',
                  style: TextStyle(
                      fontSize: 12,
                      color: cessumRed,
                      fontWeight: FontWeight.w600)),
              children: materias.map<Widget>((m) {
                final mm = Map<String, dynamic>.from(m as Map);
                return _filaMateria(mm);
              }).toList(),
            ),
          ),
        const SizedBox(height: 2),
        Text(
            _esMixta
                ? 'Mixta: marca varias materias de los atajos y usa "Agendar juntas" para impartirlas en un bloque (una invitación, un pago, una calificación). O toca una en "Ver plan completo" para cargar solo esa.'
                : 'Toca cualquier materia (los atajos de arriba o cualquiera en "Ver plan completo", incluidas las de ciclos pasados) para cargarla al formulario.',
            style: TextStyle(fontSize: 11, color: cessumFaint(context))),
      ],
    );
  }

  Widget _chipResumen(String label, dynamic valor, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text('$label: ${valor ?? 0}',
          style: TextStyle(
              fontSize: 12, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _chipMateria(Map<String, dynamic> m, String periodo, Color color) {
    final nombre = (m['denominacion'] ?? '').toString();
    // En Mixta los atajos son marcables (checkbox) para agendar varias juntas.
    if (_esMixta) {
      final k = _llaveMat(m);
      final marcada = _selAvance.containsKey(k);
      return FilterChip(
        label: Text(nombre, style: const TextStyle(fontSize: 12)),
        selected: marcada,
        showCheckmark: true,
        backgroundColor: Colors.white,
        selectedColor: const Color(0xFF6A4FB0).withOpacity(0.14),
        checkmarkColor: const Color(0xFF6A4FB0),
        side: BorderSide(
            color: marcada
                ? const Color(0xFF6A4FB0)
                : color.withOpacity(0.5)),
        onSelected: (v) {
          setState(() {
            if (v) {
              _selAvance[k] = {
                'materia': nombre,
                'clave': (m['clave'] ?? '').toString().trim(),
                'periodo': periodo,
              };
            } else {
              _selAvance.remove(k);
            }
          });
          // Al marcar, carga también la materia al formulario (Materia+Clave),
          // para que quien solo quiere UNA materia (p.ej. para juntar grupos)
          // no tenga que ir a "Ver plan completo". La última marcada manda.
          if (v) _aplicarMateria(m, periodo);
        },
      );
    }
    return ActionChip(
      label: Text(nombre, style: const TextStyle(fontSize: 12)),
      avatar: Icon(Icons.add, size: 16, color: color),
      backgroundColor: Colors.white,
      side: BorderSide(color: color.withOpacity(0.5)),
      onPressed: () => _aplicarMateria(m, periodo),
    );
  }

  // Botón "Agendar juntas": toma las materias marcadas del avance, carga la
  // primera como principal y las demás al bloque, y avisa. Solo Mixta.
  Widget _barraAgendarJuntas() {
    if (!_esMixta || _selAvance.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6A4FB0),
              foregroundColor: Colors.white),
          onPressed: _agendarJuntasDesdeAvance,
          icon: const Icon(Icons.layers, size: 18),
          label: Text('Agendar juntas (${_selAvance.length})'),
        ),
      ),
    );
  }

  void _agendarJuntasDesdeAvance() {
    final marcadas = _selAvance.values.toList();
    if (marcadas.length < 2) return;
    // La primera es la principal (va al formulario); el resto al bloque.
    final principal = marcadas.first;
    setState(() {
      _cMateria.text = principal['materia'] ?? '';
      _cClave.text = principal['clave'] ?? '';
      final per = principal['periodo'] ?? '';
      if (per.isNotEmpty) _cCiclo.text = per;
      _bloqueMaterias.clear();
      for (var i = 1; i < marcadas.length; i++) {
        _bloqueMaterias.add({
          'materia': marcadas[i]['materia'] ?? '',
          'clave': marcadas[i]['clave'] ?? '',
        });
      }
      _selAvance.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          'Bloque armado: ${_bloqueMaterias.length + 1} materias. Completa docente y fechas, luego Guardar.'),
      duration: const Duration(seconds: 3),
    ));
  }

  Widget _filaMateria(Map<String, dynamic> m) {
    final nombre = (m['denominacion'] ?? '').toString();
    final periodo = (m['periodo'] ?? '').toString();
    final estado = (m['estado'] ?? '').toString();
    final calif = m['calif'];
    Color c;
    String etq;
    IconData ic;
    if (estado == 'cursada') {
      final acred = m['acreditada'] == true;
      c = acred ? const Color(0xFF1E7D32) : cessumRed;
      etq = acred ? 'Acreditada' : 'No acreditada';
      ic = acred ? Icons.check_circle : Icons.cancel;
    } else if (estado == 'en_curso') {
      c = cessumGold;
      etq = 'En curso';
      ic = Icons.autorenew;
    } else {
      c = cessumFaint(context);
      etq = 'Pendiente';
      ic = Icons.radio_button_unchecked;
    }
    return InkWell(
      onTap: () => _aplicarMateria(m, periodo),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(children: [
          Icon(ic, size: 16, color: c),
          const SizedBox(width: 8),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(nombre, style: const TextStyle(fontSize: 12.5)),
                if (periodo.isNotEmpty)
                  Text(periodo,
                      style: TextStyle(
                          fontSize: 10.5, color: cessumFaint(context))),
              ])),
          Text(etq + (calif != null ? ' · $calif' : ''),
              style: TextStyle(
                  fontSize: 11, color: c, fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          const Icon(Icons.add_circle_outline, size: 18, color: cessumRed),
        ]),
      ),
    );
  }

  String _valProg() => _programa == _kOtro ? _cProg.text.trim() : (_programa ?? '');
  String _valGen() => _generacion == _kOtro ? _cGen.text.trim() : (_generacion ?? '');
  String _valGrupo() => _grupo == _kOtro ? _cGrupo.text.trim() : (_grupo ?? '');
  String _valTipo() => _tipo == _kOtro ? _cTipo.text.trim() : (_tipo ?? '');

  /// Mixta = periodo presencial intensivo: un BLOQUE de días seguidos, no una
  /// sesión semanal. El bloque cambia con la temporada (verano suele ser de
  /// lunes a viernes; invierno suele ser de 3 días empezando sábado o domingo;
  /// primavera suele arrancar en domingo), así que aquí no se elige "Día": los
  /// días quedan definidos por las fechas de inicio y término.
  // Mixta se detecta por el TIPO de sesiones O por el GRUPO ('1 - mixta'):
  // el usuario suele elegir la mixta por el grupo, no por el tipo, así que
  // mirar solo el tipo dejaba el panel de bloque conjunto oculto.
  bool get _esMixta =>
      _valTipo().toLowerCase().contains('mixt') ||
      _valGrupo().toLowerCase().contains('mixt');

  // Carga las materias sugeridas para el siguiente periodo/materia del grupo,
  // con el docente idóneo (prioriza a quien ya la impartió).
  Future<void> _cargarSugerencias() async {
    if (_valProg().isEmpty || _valGrupo().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Elige programa y grupo primero.')));
      return;
    }
    setState(() {
      _cargandoSugerencias = true;
      _materiasSugeridas = [];
    });
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'agendar_prospectivo_sugerir',
        'programa': _valProg(),
        'generacion': _valGen(),
        'grupo': _valGrupo(),
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      if (!mounted) return;
      final r = leerRespuesta(resp, accion: 'agendar_prospectivo_sugerir');
      if (r.ok) {
        setState(() {
          _materiasSugeridas = ((r.datos['materiasSugeridas'] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        });
        if (_materiasSugeridas.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'No hay materias pendientes sugeridas para este grupo.')));
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('No se pudo: ${r.mensaje}')));
      }
    } catch (e, s) {
      ErrorReporter.reportar(e, s, pantallaForzada: 'agenda:sugerencias_prospectivo');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Error al cargar sugerencias: revise su conexión.')));
      }
    } finally {
      if (mounted) setState(() => _cargandoSugerencias = false);
    }
  }

  // Aplica una materia+docente sugerido al formulario (el admin puede editar).
  void _aplicarSugerencia(
      Map<String, dynamic> mat, Map<String, dynamic>? doc) {
    setState(() {
      _cMateria.text = (mat['materia'] ?? '').toString();
      _cClave.text = (mat['clave'] ?? '').toString();
    });
    // (23-sep) Antes solo escribía nombre y correo: el desplegable de maestros
    // quedaba sin nadie seleccionado. _elegirSugerido lo deja elegido.
    if (doc != null) _elegirSugerido(doc);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Aplicado: ${mat['materia']}${doc != null ? ' · ${doc['nombre']}' : ''}. '
            'Ajusta fechas y guarda.'),
        duration: const Duration(seconds: 4)));
  }

  /// Se activa cuando alguien decide guardar una asignación incompleta a
  /// sabiendas. Viaja al backend para que su candado no la rechace.
  bool _forzarIncompleta = false;
  // (2-oct) La persona confirmó guardar una materia que este grupo YA tiene asignada. Vale para UN intento: _guardar la consume.
  bool _forzarDuplicada = false;

  /* ======================================================================
     (23-sep) PROPUESTA AUTOMÁTICA
     Antes, programar un grupo pedía: pulsar «Sugerencias», elegir materia y
     docente, elegir el lunes de inicio y adivinar si el docente estaba libre
     (el choque aparecía hasta guardar). Ahora, al abrir una asignación nueva
     con programa y grupo, el formulario llega armado y dice por qué:
       · día y hora: los de la materia anterior del grupo
       · fechas: continúan tras la materia anterior + receso (_rangoSugerido)
       · materia: la siguiente pendiente del plan (agendar_prospectivo_sugerir)
       · docente: el que más la ha impartido Y está libre ese día y hora
         (maestros_disponibles); a los ocupados los salta y dice por qué.
     Nada se guarda solo: el administrador revisa y guarda.
     ====================================================================== */
  bool _armandoPropuesta = false;
  final List<String> _propuestaRazones = [];

  /* ======================================================================
     (23-sep) HISTORIAL DEL GRUPO · solo informativo, no bloquea nada.
     Qué materias se le han programado al grupo y qué profesores le han dado
     clase, para no repetir. Sale de las asignaciones que la agenda ya tiene
     cargadas: no hace consultas. Si no hay generación elegida, muestra todas
     las generaciones de ese programa y grupo, cada una con su etiqueta.
     ====================================================================== */
  List<Map<String, dynamic>> _historialGrupo() {
    final np = _normaPrograma(_valProg());
    final gen = _valGen().trim();
    final gr = _normaPrograma(_valGrupo());
    if (np.isEmpty || gr.isEmpty) return const [];
    final filaEditada = widget.existente == null ? null : '${widget.existente!['fila']}';
    final l = widget.asignaciones.where((a) {
      if (_normaPrograma('${a['programa'] ?? ''}') != np) return false;
      if (_normaPrograma('${a['grupo'] ?? ''}') != gr) return false;
      if (gen.isNotEmpty && '${a['generacion'] ?? ''}'.trim() != gen) return false;
      if (filaEditada != null && '${a['fila']}' == filaEditada) return false; // la que se está editando
      return '${a['materia'] ?? ''}'.trim().isNotEmpty;
    }).toList();
    l.sort((x, y) => '${y['inicio'] ?? ''}'.compareTo('${x['inicio'] ?? ''}'));
    return l;
  }

  static String _estadoAsig(Map<String, dynamic> a) =>
      '${a['invitacionEstado'] ?? a['estado'] ?? ''}'.trim().toLowerCase();

  String _fechaCorta(String iso) {
    final d = _fechaIso(iso);
    if (d == null) return iso;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  /* (2-oct) HISTORIAL DEL GRUPO, COMPLETO Y SIN DUPLICADAS.
     · Una fila SIN profesor ni correo de una materia que el grupo ya tiene en otra
       fila (misma generación) es una DUPLICADA: se muestra aparte, sin contarla
       arriba, con su número de fila para poder eliminarla desde la agenda.
     · Las materias que el grupo ya cursó según sus calificaciones pero no tienen
       fila en la agenda (grupos que cursaron sus primeros semestres sin
       asignaciones) se piden al Guardián (historial_grupo_calif, SOLO LECTURA) y se
       listan al final, sin profesor ni fechas. No se escribe nada en la hoja.
     · Una fila histórica inerte (si existiera) no cuenta como profesor. */
  static bool _esHistorica(Map<String, dynamic> a) {
    final correo = '${a['correo'] ?? ''}'.trim().toLowerCase();
    final notas = '${a['notas'] ?? ''}'.trim().toLowerCase();
    return correo.endsWith('@sin-docente.invalid') || notas.startsWith('reconstruido desde calificaciones');
  }

  static bool _sinProfesor(Map<String, dynamic> a) =>
      '${a['docente'] ?? ''}'.trim().isEmpty && '${a['correo'] ?? ''}'.trim().isEmpty && !_esHistorica(a);

  String _claveMateria(Map<String, dynamic> a) =>
      '${a['generacion'] ?? ''}'.trim() + '|' + _normaPrograma('${a['materia'] ?? ''}');

  /// Devuelve [las que cuentan, las duplicadas sin profesor].
  List<List<Map<String, dynamic>>> _separarDuplicadas(List<Map<String, dynamic>> filas) {
    final conDato = <String>{};
    for (final a in filas) {
      if (!_sinProfesor(a)) conDato.add(_claveMateria(a));
    }
    final cuentan = <Map<String, dynamic>>[];
    final duplicadas = <Map<String, dynamic>>[];
    final yaSinProfe = <String>{};
    for (final a in filas) {
      if (!_sinProfesor(a)) {
        cuentan.add(a);
        continue;
      }
      final k = _claveMateria(a);
      if (conDato.contains(k) || yaSinProfe.contains(k)) {
        duplicadas.add(a);
      } else {
        yaSinProfe.add(k);
        cuentan.add(a);
      }
    }
    return [cuentan, duplicadas];
  }

  Future<void> _cargarHistorialCalif() async {
    final prog = _valProg();
    final gen = _valGen().trim();
    final gr = _valGrupo();
    final clave = '$prog|$gen|$gr';
    if (prog.isEmpty || gen.isEmpty || gr.isEmpty || clave == _histCalifClave) return;
    _histCalifClave = clave;
    if (mounted && _histCalif.isNotEmpty) setState(() => _histCalif = []);
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'historial_grupo_calif',
        'programa': prog,
        'generacion': gen,
        'grupo': gr,
        'actor': await SessionStore.realEmail() ?? '',
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 25));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted || clave != _histCalifClave) return;
      if (data['ok'] == true) {
        setState(() {
          _histCalif = ((data['materias'] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .where((m) => m['tieneFila'] != true)
              .toList();
        });
      }
    } catch (_) {
      // Solo informativo: si no responde, el historial muestra lo que ya tiene la agenda.
    }
  }

  Widget _historialGrupoUI() {
    // (2-oct) Se piden al Guardián las materias que el grupo cursó según sus calificaciones.
    if (_valProg().isNotEmpty &&
        _valGen().trim().isNotEmpty &&
        _valGrupo().isNotEmpty &&
        '${_valProg()}|${_valGen().trim()}|${_valGrupo()}' != _histCalifClave) {
      Future.microtask(_cargarHistorialCalif);
    }
    final hist = _historialGrupo();
    final todasVigentes = hist.where((a) => _estadoAsig(a) != 'rechazada').toList();
    final rechazadas = hist.where((a) => _estadoAsig(a) == 'rechazada').toList();
    final separadas = _separarDuplicadas(todasVigentes);
    final vigentes = separadas[0];
    final duplicadas = separadas[1];
    final genSel = _valGen().trim();
    // Materias reconstruidas desde calificaciones, de la más reciente a la más antigua del plan.
    // Una materia que ya tiene fila en la agenda (aunque sea sin profesor) no se repite como reconstruida.
    final yaEnHist = <String>{for (final a in hist) _normaPrograma('${a['materia'] ?? ''}')};
    final recon = _histCalif.where((m) => !yaEnHist.contains(_normaPrograma('${m['materia'] ?? ''}'))).toList()
      ..sort((x, y) => (num.tryParse('${y['orden'] ?? ''}') ?? 0).compareTo(num.tryParse('${x['orden'] ?? ''}') ?? 0));
    final nMaterias = <String>{for (final a in vigentes) _claveMateria(a)}.length + recon.length;
    // Profesores que le han dado clase (sin contar invitaciones rechazadas ni filas históricas).
    final porProfe = <String, Map<String, dynamic>>{};
    for (final a in vigentes) {
      if (_esHistorica(a)) continue;
      final c = '${a['correo'] ?? ''}'.trim().toLowerCase();
      final nom = '${a['docente'] ?? ''}'.trim();
      final k = c.isNotEmpty ? c : nom.toLowerCase();
      if (k.isEmpty) continue;
      final p = porProfe.putIfAbsent(k, () => {'nombre': nom.isEmpty ? c : nom, 'n': 0, 'materias': <String>[]});
      p['n'] = (p['n'] as int) + 1;
      (p['materias'] as List<String>).add('${a['materia']}');
    }
    final profes = porProfe.values.toList()..sort((x, y) => (y['n'] as int).compareTo(x['n'] as int));

    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF2B6CB0).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2B6CB0).withValues(alpha: 0.30)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Avisos que se actualizan mientras se escribe la materia o se elige al profesor.
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _cMateria,
          builder: (_, vMat, __) => ValueListenableBuilder<TextEditingValue>(
            valueListenable: _cCorreo,
            builder: (_, vCor, __) {
              final avisos = <Widget>[];
              final mat = _normaPrograma(vMat.text);
              if (mat.isNotEmpty) {
                final repetidas = vigentes.where((a) => _normaPrograma('${a['materia'] ?? ''}') == mat).toList();
                for (final a in repetidas) {
                  final quien = '${a['docente'] ?? ''}'.isNotEmpty ? '${a['docente']}' : 'sin profesor';
                  final cuando = '${a['inicio'] ?? ''}'.trim().isEmpty
                      ? '.'
                      : ', del ${_fechaCorta('${a['inicio'] ?? ''}')} al ${_fechaCorta('${a['termino'] ?? ''}')}.';
                  avisos.add(_avisoHist(
                      Icons.repeat,
                      const Color(0xFFB7791F),
                      _esHistorica(a)
                          ? 'Esta materia ya la cursó este grupo (reconstruida desde sus calificaciones).'
                          : 'Esta materia ya se le programó a este grupo'
                              '${genSel.isEmpty ? ' (generación ${a['generacion']})' : ''}: $quien$cuando'));
                }
                for (final m in recon) {
                  if (_normaPrograma('${m['materia'] ?? ''}') == mat) {
                    avisos.add(_avisoHist(Icons.repeat, const Color(0xFFB7791F),
                        'Esta materia ya la cursó este grupo, según sus calificaciones (no tiene fila en la agenda).'));
                  }
                }
              }
              final cor = vCor.text.trim().toLowerCase();
              if (cor.isNotEmpty && porProfe.containsKey(cor)) {
                final p = porProfe[cor]!;
                final mats = (p['materias'] as List<String>).toSet().toList();
                avisos.add(_avisoHist(
                    Icons.person_search_outlined,
                    const Color(0xFF2B6CB0),
                    '${p['nombre']} ya le ha dado ${p['n']} materia(s) a este grupo: ${mats.join(', ')}.'));
              }
              if (avisos.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: avisos),
              );
            },
          ),
        ),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            leading: const Icon(Icons.history_edu_outlined, color: Color(0xFF2B6CB0)),
            title: Text(
                'Historial del grupo: $nMaterias materia(s) · ${profes.length} profesor(es)',
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800)),
            subtitle: Text(
                (genSel.isEmpty
                        ? 'Solo informativo · todas las generaciones de este grupo'
                        : 'Solo informativo · para no repetir materias ni profesores') +
                    (recon.isEmpty ? '' : ' · ${recon.length} reconstruida(s) desde calificaciones'),
                style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
            children: [
              if (hist.isEmpty && recon.isEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Este grupo todavía no tiene materias programadas.',
                      style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
                )
              else ...[
                if (profes.isNotEmpty) ...[
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Profesores que le han dado clase',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final p in profes)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text('${p['nombre']} · ${p['n']}', style: const TextStyle(fontSize: 11.5)),
                        ),
                    ]),
                  ),
                  const SizedBox(height: 10),
                ],
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Materias programadas, de la más reciente a la más antigua',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 4),
                for (final a in vigentes) _filaHist(a, genSel.isEmpty),
                for (final m in recon) _filaCalif(m),
                if (duplicadas.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Posibles duplicadas sin profesor (no se cuentan arriba)',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cessumMuted(context))),
                  ),
                  for (final a in duplicadas) _filaHist(a, genSel.isEmpty, apagada: true, extra: ' · fila ${a['fila']}'),
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('Si ya no hacen falta, se pueden eliminar desde la agenda (busque esa materia en este grupo).',
                        style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
                  ),
                ],
                if (rechazadas.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Invitaciones rechazadas (no cuentan como impartidas)',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cessumMuted(context))),
                  ),
                  for (final a in rechazadas) _filaHist(a, genSel.isEmpty, apagada: true),
                ],
              ],
            ],
          ),
        ),
      ]),
    );
  }

  Widget _avisoHist(IconData icono, Color color, String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icono, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(texto, style: TextStyle(fontSize: 12.5, color: color, fontWeight: FontWeight.w600, height: 1.35)),
          ),
        ]),
      );

  Widget _filaHist(Map<String, dynamic> a, bool conGen, {bool apagada = false, String extra = ''}) {
    final est = _estadoAsig(a);
    final etiqueta = est == 'pendiente' ? ' · invitación pendiente' : '';
    final color = apagada ? cessumMuted(context) : null;
    final quien = _esHistorica(a)
        ? 'reconstruida desde calificaciones'
        : ('${a['docente'] ?? ''}'.isNotEmpty ? '${a['docente']}' : 'sin profesor');
    final fechas = '${a['inicio'] ?? ''}'.trim().isEmpty
        ? ''
        : ' · ${_fechaCorta('${a['inicio'] ?? ''}')} a ${_fechaCorta('${a['termino'] ?? ''}')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('•  ', style: TextStyle(fontSize: 12.5, color: color)),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '${a['materia']}', style: TextStyle(fontWeight: FontWeight.w700, color: color)),
              TextSpan(
                  text: ' · $quien${conGen ? ' · gen. ${a['generacion']}' : ''}$fechas$etiqueta$extra',
                  style: TextStyle(color: color ?? cessumMuted(context))),
            ]),
            style: const TextStyle(fontSize: 12.5, height: 1.35),
          ),
        ),
      ]),
    );
  }

  /// (2-oct) Materia que el grupo ya cursó según sus calificaciones y no tiene fila en la agenda.
  Widget _filaCalif(Map<String, dynamic> m) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('•  ', style: TextStyle(fontSize: 12.5)),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '${m['materia']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(
                  text: ' · según calificaciones · sin profesor ni fechas en la agenda',
                  style: TextStyle(color: cessumMuted(context))),
            ]),
            style: const TextStyle(fontSize: 12.5, height: 1.35),
          ),
        ),
      ]),
    );
  }

  /* (23-sep) ¿SE VERIFICÓ LA DISPONIBILIDAD? Antes, si maestros_disponibles
     fallaba, el error se tragaba: la lista de ocupados quedaba vacía y TODOS
     parecían libres, sin aviso. Ahora se distingue:
       _dispVerificada → el Guardián respondió para este día, hora y fechas
       _dispFallo      → había día y hora, pero la consulta no respondió */
  bool _dispVerificada = false;
  bool _dispFallo = false;

  /* (23-sep) ALUMNOS DEL CURSO. Con programa, generación y grupo: la lista
     exacta del curso (ruta alumnos, que con la materia incluye a quienes la
     recursan con ese grupo). Con solo el programa (o programa y generación):
     el padrón de ese programa agrupado por generación y grupo, sin bajas ni
     egresados (grupos_admin_todos, que se pide una sola vez). */
  List<Map<String, dynamic>>? _padronTodos;

  Future<List<Map<String, dynamic>>> _cargarAlumnosCurso(
      String prog, String gen, String grupo, String materia, bool exacto) async {
    if (exacto) {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'alumnos',
        'programa': prog,
        'generacion': gen,
        'grupo': grupo,
        if (materia.isNotEmpty) 'materia': materia,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final l = ((data['alumnos'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      l.sort((a, b) => '${a['nombre']}'.compareTo('${b['nombre']}'));
      return l;
    }
    if (_padronTodos == null) {
      final resp = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'grupos_admin_todos'}))
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      _padronTodos = ((data['grupos'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    final out = <Map<String, dynamic>>[];
    for (final m in _padronTodos!) {
      if (_normaPrograma('${m['programa'] ?? ''}') != _normaPrograma(prog)) continue;
      if (gen.isNotEmpty && '${m['generacion'] ?? ''}'.trim() != gen.trim()) continue;
      final gr = '${m['grupo'] ?? ''}'.trim();
      final gu = gr.toUpperCase();
      if (gu == 'BAJA' || gu.startsWith('EGRESAD') || gu.startsWith('CONCLUID')) continue;
      out.add({...m, 'seccion': 'Generación ${m['generacion']} · grupo $gr'});
    }
    out.sort((a, b) {
      final c = '${a['seccion']}'.compareTo('${b['seccion']}');
      return c != 0 ? c : '${a['nombre']}'.compareTo('${b['nombre']}');
    });
    return out;
  }

  Future<void> _verAlumnosDelCurso() async {
    final prog = _valProg(), gen = _valGen(), grupo = _valGrupo(), materia = _cMateria.text.trim();
    final exacto = gen.isNotEmpty && grupo.isNotEmpty;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _HojaAlumnosCurso(
        titulo: exacto ? '$prog · $gen · grupo $grupo' : (gen.isNotEmpty ? '$prog · $gen' : prog),
        nota: exacto
            ? 'Alumnos inscritos en el grupo y quienes recursan alguna materia con él (marcados). Sin bajas.'
            : 'Todos los grupos del programa${gen.isNotEmpty ? ' en esa generación' : ''}, sin bajas ni egresados. '
                'Elija generación y grupo para ver el curso exacto.',
        cargar: () => _cargarAlumnosCurso(prog, gen, grupo, materia, exacto),
      ),
    );
  }

  Future<void> _armarPropuesta() async {
    if (widget.existente != null) return;
    if (_valProg().isEmpty || _valGrupo().isEmpty) return;
    if (_cMateria.text.trim().isNotEmpty) return;
    setState(() {
      _armandoPropuesta = true;
      _propuestaRazones.clear();
    });
    final razones = <String>[];
    try {
      // (30-sep-2026) REESCRITO — antes la hora SIEMPRE se copiaba de la
      // materia de término más reciente, sin ver si esa franja ya estaba
      // ocupada: en el caso real (Educación Inclusiva 26-1 grupo 2) copiaba
      // 11:30-13:00 (la franja YA TOMADA por Ajustes Razonables) en vez de
      // proponer 10:00-11:30 (la libre del mismo bloque). Ahora, en
      // sabatino de posgrado: si el bloque que _rangoSugerido() devuelve
      // tiene hueco (coincide en fechas con una asignación existente pero
      // le falta una franja), la hora propuesta es la que FALTA, no la de
      // "la anterior". Fuera de ese caso (bloque nuevo, sin hueco) se
      // mantiene el comportamiento de siempre: día/hora de la materia
      // anterior del grupo.
      Map<String, dynamic>? anterior;
      DateTime? finAnt;
      for (final a in widget.asignaciones) {
        if (_normaPrograma('${a['programa'] ?? ''}') != _normaPrograma(_valProg())) continue;
        if ('${a['generacion'] ?? ''}'.trim() != _valGen().trim()) continue;
        if ('${a['grupo'] ?? ''}'.trim() != _valGrupo().trim()) continue;
        final f = _fechaIso('${a['termino'] ?? ''}');
        if (f != null && (finAnt == null || f.isAfter(finAnt))) {
          finAnt = f;
          anterior = a;
        }
      }

      // 1) Fechas primero: de ahí se sabe si hay un hueco que llenar.
      final r = _rangoSugerido();
      String? franjaLibre;
      if (r != null) {
        final esSabatinoPosgrado = _bloquesHorario.length == 2 && !_esLicenciatura;
        if (esSabatinoPosgrado) {
          // (2-oct-2026) Mismo bloque = mismo TÉRMINO, comparado como fecha (no
          // como texto), y las horas se comparan normalizadas: «11:30-13:00»
          // (capturada a mano) y «11:30 - 13:00» son la misma franja. Antes una
          // franja tecleada sin espacios parecía libre y se podía proponer encima.
          final finBloque = _fechaIso(r['fin'] ?? '');
          final ocupadasEseRango = <String>{};
          for (final a in widget.asignaciones) {
            if (_normaPrograma('${a['programa'] ?? ''}') != _normaPrograma(_valProg())) continue;
            if ('${a['generacion'] ?? ''}'.trim() != _valGen().trim()) continue;
            if ('${a['grupo'] ?? ''}'.trim() != _valGrupo().trim()) continue;
            final finA = _fechaIso('${a['termino'] ?? ''}');
            if (finBloque == null || finA == null || finA != finBloque) continue;
            ocupadasEseRango.add(_normHoraFranja('${a['hora'] ?? ''}'));
          }
          if (ocupadasEseRango.isNotEmpty) {
            // Hay al menos una materia ya en este rango: es un bloque con
            // hueco. La franja propuesta es la que NO está ocupada.
            for (final h in _bloquesHorario) {
              if (!ocupadasEseRango.contains(_normHoraFranja(h))) { franjaLibre = h; break; }
            }
          }
        }
        if (_cInicio.text.trim().isEmpty) {
          final ini = _fechaIso(r['inicio'] ?? '');
          if (ini != null) {
            _aplicarInicioLunes(ini);
            if (franjaLibre != null) {
              razones.add('Fechas: del ${_cInicio.text} al ${_cTermino.text} — mismo bloque vigente del '
                  'grupo, que todavía tiene una franja libre.');
            } else {
              razones.add('Fechas: del ${_cInicio.text} al ${_cTermino.text}, después de '
                  '${anterior != null ? '«${anterior['materia']}»' : 'su materia anterior'} y el receso.');
            }
          }
        }
      }

      // 2) Día y hora: la franja libre del bloque con hueco si se encontró;
      // si no, la de la materia anterior del grupo, como siempre.
      if (franjaLibre != null) {
        if (_dia == null) _dia = 'Sábado';
        if (_cHora.text.trim().isEmpty) _cHora.text = franjaLibre;
        razones.add('Día y hora: Sábado $franjaLibre — la franja que todavía está libre en este bloque.');
      } else if (anterior != null) {
        final d = '${anterior['dia'] ?? ''}';
        final h = '${anterior['hora'] ?? ''}'.trim();
        if (_dia == null && _dias.contains(d)) _dia = d;
        if (_cHora.text.trim().isEmpty && h.isNotEmpty) _cHora.text = h;
        if (_dia != null || _cHora.text.trim().isNotEmpty) {
          razones.add('Día y hora: ${_dia ?? ''} ${_cHora.text.trim()}, como su materia anterior («${anterior['materia']}»).');
        }
      }
      // 3) Materia siguiente del plan y docente que la ha impartido y está libre.
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'agendar_prospectivo_sugerir',
        'programa': _valProg(),
        'generacion': _valGen(),
        'grupo': _valGrupo(),
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      // (28-sep, Fase 3) Antes, si el servidor respondía ok:false, el código
      // ni lo miraba: leía materiasSugeridas (vacío) y decía «el plan no
      // tiene materias pendientes», que es un motivo distinto y falso.
      final rSug = leerRespuesta(resp, accion: 'agendar_prospectivo_sugerir');
      final mats = rSug.ok
          ? ((rSug.datos['materiasSugeridas'] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      if (!rSug.ok) {
        razones.add('Materia: no se pudo consultar el plan (${rSug.mensaje}); llénela a mano.');
      } else if (mats.isEmpty) {
        razones.add('Materia: el plan no tiene materias pendientes para este grupo; revise el avance abajo.');
      } else {
        _materiasSugeridas = mats;
        if (_profes.isEmpty) await _cargarProfes();
        await _cargarDisponibilidad(); // con el día, la hora y las fechas ya puestos
        await _cargarBloquesGrupo();
        if (!mounted) return;
        final mat = mats.first;
        _cMateria.text = '${mat['materia'] ?? ''}';
        _cClave.text = '${mat['clave'] ?? ''}';
        razones.add('Materia: «${mat['materia']}», la siguiente pendiente del plan'
            '${'${mat['periodo'] ?? ''}'.isNotEmpty ? ' (periodo ${mat['periodo']})' : ''}.');
        final docs = ((mat['docentesSugeridos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        Map<String, dynamic>? elegido;
        final saltados = <String>[];
        final verificada = _dispVerificada;
        for (final d in docs) {
          final c = '${d['correo'] ?? ''}'.toLowerCase();
          if (verificada && c.isNotEmpty && _ocupados.contains(c)) {
            final mot = _conflicto[c] ?? '';
            saltados.add('${d['nombre']}${mot.isNotEmpty ? ' ($mot)' : ' (ocupado a esa hora)'}');
            continue;
          }
          elegido = d;
          break;
        }
        if (elegido != null) {
          _elegirSugerido(elegido);
          final sinDiaHora = _dia == null || _cHora.text.trim().isEmpty;
          razones.add('Profesor: ${elegido['nombre']} — ${elegido['motivo'] ?? 'sugerido'}'
              '${verificada ? '; está libre ese día y hora' : ''}.'
              '${saltados.isNotEmpty ? ' Se saltó a ${saltados.join(', ')}, porque tienen choque.' : ''}'
              '${!verificada && sinDiaHora ? ' Falta el día y la hora para revisar si está libre.' : ''}'
              '${!verificada && !sinDiaHora ? ' ⚠ No se pudo revisar su disponibilidad: el choque se validará al guardar.' : ''}');
        } else if (docs.isNotEmpty) {
          razones.add('Profesor: los que ya la impartieron tienen choque a esa hora '
              '(${saltados.join(', ')}). Elija otro en la lista o cambie el horario.');
        } else {
          razones.add('Profesor: nadie la ha impartido antes; elíjalo en la lista de maestros.');
        }
      }
    } catch (e, s) {
      ErrorReporter.reportar(e, s, pantallaForzada: 'agenda:armar_propuesta');
      razones.add('No se pudo completar la propuesta: revise su conexión y llene lo que falte a mano.');
    }
    if (!mounted) return;
    setState(() {
      _armandoPropuesta = false;
      _propuestaRazones
        ..clear()
        ..addAll(razones);
    });
  }

  void _descartarPropuesta() {
    setState(() {
      _cMateria.clear();
      _cClave.clear();
      _cDocente.clear();
      _cCorreo.clear();
      _maestroSelCorreo = null;
      _propuestaRazones.clear();
    });
  }

  Widget _bannerPropuesta() {
    if (widget.existente != null) return const SizedBox.shrink();
    if (_armandoPropuesta) {
      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF6A1B9A).withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(children: [
          SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6A1B9A))),
          SizedBox(width: 10),
          Expanded(
            child: Text('Armando una propuesta con el plan de estudios, el historial de los profesores y su disponibilidad…',
                style: TextStyle(fontSize: 12.5)),
          ),
        ]),
      );
    }
    if (_propuestaRazones.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF6A1B9A).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF6A1B9A).withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.auto_awesome, color: Color(0xFF6A1B9A), size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text('Propuesta automática: revise y guarde',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Color(0xFF6A1B9A))),
          ),
        ]),
        const SizedBox(height: 6),
        for (final r in _propuestaRazones)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text('• $r', style: const TextStyle(fontSize: 12.5, height: 1.35)),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _descartarPropuesta,
            child: const Text('Quitar materia y profesor propuestos'),
          ),
        ),
      ]),
    );
  }

  /// (23-sep) Listas largas con buscador (programas, generaciones).
  Future<String?> _elegirConBusqueda(String titulo, List<String> opciones, {bool permitirOtro = true}) async {
    final ctl = TextEditingController();
    final r = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final q = _normaPrograma(ctl.text);
        final lista = opciones.where((o) => q.isEmpty || _normaPrograma(o).contains(q)).toList();
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.7,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: TextField(
                  controller: ctl,
                  autofocus: true,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Buscar $titulo',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onChanged: (_) => setS(() {}),
                ),
              ),
              Expanded(
                child: ListView(children: [
                  for (final o in lista)
                    ListTile(dense: true, title: Text(o), onTap: () => Navigator.pop(ctx, o)),
                  if (permitirOtro)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.edit_outlined, size: 18),
                      title: const Text('Otro…'),
                      onTap: () => Navigator.pop(ctx, _kOtro),
                    ),
                ]),
              ),
            ]),
          ),
        );
      }),
    );
    ctl.dispose();
    return r;
  }

  Future<void> _guardar({bool soloValidar = false}) async {
    _forzarIncompleta = false;
    // (2-oct) Se consume aquí para que valga solo para este intento (si el servidor pide otra confirmación, no se arrastra).
    final forzarDuplicadaEsteIntento = _forzarDuplicada;
    _forzarDuplicada = false;
    if (_valProg().isEmpty || _valGrupo().isEmpty || _cMateria.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Programa, grupo y materia son obligatorios.')));
      return;
    }

    /* (ago-21) LO QUE FALTA SE AVISA AQUÍ, NO DESPUÉS.
     *
     * Una asignación incompleta no falla al guardarse: falla semanas después
     * y en cosas que nadie relaciona con ella.
     *
     *   · Sin FECHA DE TÉRMINO, el generador de Meet crea 15 semanas por
     *     omisión. Un curso de cinco sesiones queda con once invitaciones de
     *     más, y a los alumnos les llegan recordatorios de clases que no
     *     existen.
     *
     *   · Sin DOCENTE, sus calificaciones llegan al reporte de la SEC sin
     *     CURP. Eso fueron miles de filas.
     *
     * El backend también lo frena, pero avisar aquí evita el viaje: se
     * corrige con el formulario enfrente y no con un error de vuelta.
     */
    final faltan = <String>[];
    if (_cInicio.text.trim().isEmpty) faltan.add('fecha de inicio');
    if (_cTermino.text.trim().isEmpty) faltan.add('fecha de término');
    if (faltan.isNotEmpty) {
      final seguir = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Falta información',
              style: TextStyle(fontSize: 16)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Falta: ${faltan.join(', ')}.',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 10),
            const Text(
                'Sin fecha de término, las sesiones de Meet se generan a '
                'ciegas: 15 semanas por omisión. En un curso de cinco '
                'sesiones son once invitaciones de más, y los alumnos '
                'reciben recordatorios de clases que no existen.',
                style: TextStyle(fontSize: 12.5, height: 1.5)),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Volver y completar')),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: cessumRed),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar así'),
            ),
          ],
        ),
      );
      if (seguir != true) return;
      // Se eligió guardar así: el backend también frena lo incompleto, y sin
      // esta bandera devolvería el mismo aviso desde el otro lado.
      _forzarIncompleta = true;
    }
    if (_directo && _esMixta && _cHora.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Para asignar directo necesitas indicar el horario.')));
      return;
    }
    if (_directo &&
        !_esMixta &&
        ((_dia ?? '').isEmpty || _cHora.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Para asignar directo necesitas indicar el día y la hora.')));
      return;
    }
    // (2-oct-2026) ÚLTIMA REVISIÓN DE FECHAS, SOLO SI HAY ALGO QUE REVISAR.
    // Un error de fechas no falla al guardar: se descubre cuando el calendario
    // ya mandó invitaciones a toda la generación. Aquí se muestran las sesiones
    // reales y los avisos, y se deja corregir o guardar a sabiendas. Una
    // asignación ya existente solo se revisa si cambió inicio, término o día.
    if (!soloValidar && !_esMixta) {
      final esEd0 = widget.existente != null && widget.existente!['fila'] != null;
      var revisar = !esEd0;
      if (esEd0) {
        final ex = widget.existente!;
        revisar = _fechaIso(_cInicio.text.trim()) != _fechaIso('${ex['inicio'] ?? ''}') ||
            _fechaIso(_cTermino.text.trim()) != _fechaIso('${ex['termino'] ?? ''}') ||
            (_dia ?? '') != '${ex['dia'] ?? ''}';
      }
      final avisosF = revisar ? _avisosDeFechas() : <_AvisoFecha>[];
      if (avisosF.isNotEmpty) {
        final ini0 = _fechaIso(_cInicio.text.trim());
        final fin0 = _fechaIso(_cTermino.text.trim());
        final wd0 = _weekdayDeDia(_dia);
        final ses0 = (ini0 == null || fin0 == null || wd0 == null)
            ? <DateTime>[]
            : _fechasDeSesiones(ini0, fin0, wd0);
        final listaSes = ses0.map(_fechaDiaTxt).join(' · ');
        final seguirF = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Revisa las fechas antes de guardar',
                style: TextStyle(fontSize: 16)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (ses0.isNotEmpty) ...[
                    Text('Se crearían ${ses0.length} sesión(es): $listaSes',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 12.5, height: 1.4)),
                    const SizedBox(height: 10),
                  ],
                  for (final av in avisosF)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                              av.grave ? Icons.error_outline : Icons.warning_amber_rounded,
                              size: 16,
                              color: av.grave
                                  ? const Color(0xFFC62828)
                                  : const Color(0xFFB26A00)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(av.texto,
                                style: const TextStyle(fontSize: 12.5, height: 1.4)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Corregir fechas')),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: cessumRed),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Guardar así'),
              ),
            ],
          ),
        );
        if (seguirF != true) return;
      }
    }
    setState(() => _guardando = true);
    // BLOQUE CONJUNTO (Mixta): si hay materias adicionales y NO es edición,
    // se manda asignacion_guardar_bloque con la lista completa (principal +
    // adicionales). Una invitación, un pago, una calificación que se replica.
    final esEdicion = widget.existente != null && widget.existente!['fila'] != null;
    final usarBloque = _esMixta && _bloqueMaterias.isNotEmpty && !esEdicion;
    // Juntar grupos: misma materia+profesor a varios grupos (una invitación,
    // pero cada grupo su acta). Tiene prioridad sobre el guardado normal.
    final usarGruposJuntos =
        _esMixta && _gruposJuntos.isNotEmpty && !esEdicion && !usarBloque;

    final payload = <String, dynamic>{
      'accion': usarBloque
          ? 'asignacion_guardar_bloque'
          : usarGruposJuntos
              ? 'asignacion_guardar_grupos'
              : 'asignacion_guardar',
      // Solo cuando se aceptó guardar incompleta a sabiendas.
      if (_forzarIncompleta) 'forzar': true,
      // Solo cuando se confirmó guardar una materia que el grupo ya tiene asignada.
      if (forzarDuplicadaEsteIntento) 'forzarDuplicada': true,
      'programa': _valProg(),
      'generacion': _valGen(),
      'grupo': _valGrupo(),
      'periodo': _periodo ?? '',
      'tipoSesiones': _valTipo(),
      'dia': _dia ?? '',
      'hora': _cHora.text.trim(),
      'materia': _cMateria.text.trim(),
      'clave': _cClave.text.trim(),
      'ciclo': _cCiclo.text.trim(),
      'docente': _cDocente.text.trim(),
      'correo': _cCorreo.text.trim(),
      'directo': _directo,
      'prospectivo': _prospectivo,
      'inicio': _cInicio.text.trim(),
      'termino': _cTermino.text.trim(),
      'activa': _activa ? 'SI' : 'NO',
      'notas': _cNotas.text.trim(),
      'linkLlamada': _cLlamada.text.trim(),
      'linkAula': _cAula.text.trim(),
    };
    if (usarBloque) {
      // Lista completa: la principal del formulario + las adicionales.
      final materias = <Map<String, String>>[
        {'materia': _cMateria.text.trim(), 'clave': _cClave.text.trim()},
        ..._bloqueMaterias,
      ];
      payload['materias'] = jsonEncode(materias);
    }
    if (usarGruposJuntos) {
      // Lista completa: el grupo del formulario + los adicionales.
      final grupos = <Map<String, String>>[
        {
          'programa': _valProg(),
          'generacion': _valGen(),
          'grupo': _valGrupo(),
          'tipoSesiones': _valTipo(),
        },
        ..._gruposJuntos,
      ];
      payload['grupos'] = jsonEncode(grupos);
    }
    if (esEdicion) {
      payload['fila'] = widget.existente!['fila'];
    }
    // (23-sep) REVISAR CON EL GUARDIÁN: los mismos datos que se guardarían,
    // con soloValidar. Pasa por todos sus candados y no escribe nada: una sola
    // fuente de verdad, en lugar de adivinar aquí lo que el Guardián rechazará.
    if (soloValidar) {
      if (payload['accion'] != 'asignacion_guardar') {
        setState(() => _guardando = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('La revisión previa es para asignaciones individuales. '
                'En bloques y grupos juntos, el Guardián valida al guardar.'),
            duration: Duration(seconds: 6)));
        return;
      }
      payload['soloValidar'] = true;
      try {
        final rv = await http
            .post(Uri.parse(guardianUrl),
                headers: {'Content-Type': 'text/plain;charset=utf-8'},
                body: jsonEncode(payload))
            .timeout(const Duration(seconds: 75));
        final dv = jsonDecode(rv.body) as Map<String, dynamic>;
        if (!mounted) return;
        setState(() => _guardando = false);
        final ok = dv['ok'] == true;
        final avisos = ((dv['avisos'] as List?) ?? const []).map((x) => '$x').toList();
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(children: [
              Icon(ok ? Icons.check_circle : (dv['choqueDocente'] == true ? Icons.warning_amber : Icons.block),
                  color: ok ? const Color(0xFF1E7F52) : (dv['choqueDocente'] == true ? Colors.orange.shade800 : cessumRed)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    ok
                        ? 'Todo en orden'
                        : (dv['choqueDocente'] == true ? 'Posible choque del profesor' : 'El Guardián la rechazaría'),
                    style: const TextStyle(fontSize: 16)),
              ),
            ]),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ok ? '${dv['nota'] ?? 'Pasó todas las validaciones.'}' : '${dv['error'] ?? 'No pasó la validación.'}',
                  style: const TextStyle(fontSize: 13.5, height: 1.4)),
              if (!ok && dv['choqueDocente'] == true)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Es un aviso: al guardar podrá asignarla de todas formas.',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
              for (final a in avisos)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('• $a', style: const TextStyle(fontSize: 12.5)),
                ),
            ]),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido'))],
          ),
        );
      } catch (e, st) {
        // (28-sep, Fase 3) El mensaje ya era bueno; solo faltaba el reporte.
        ErrorReporter.reportar(e, st, pantallaForzada: 'agenda:revisar_soloValidar');
        if (mounted) {
          setState(() => _guardando = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('No se pudo revisar con el Guardián. Revise su conexión.'),
              duration: Duration(seconds: 6)));
        }
      }
      return;
    }
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode(payload))
          .timeout(const Duration(seconds: 75));
      // (28-sep, Fase 3) leerRespuesta distingue HTML/timeout de un rechazo
      // real, y reporta sola cuando la respuesta no se pudo interpretar —
      // este es el botón de GUARDAR: el más usado de toda la pantalla.
      final rg = leerRespuesta(resp, accion: 'asignacion_guardar');
      // Choque del MISMO DOCENTE: es un aviso, no un bloqueo. Se pregunta si
      // desea asignar de todas formas y, si acepta, se reintenta con forzar.
      if (!rg.ok && rg['choqueDocente'] == true) {
        if (!mounted) return;
        setState(() => _guardando = false);
        final confirmar = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Posible choque de horario',
                style: TextStyle(fontSize: 16)),
            content: Text(rg.mensaje.isNotEmpty
                ? rg.mensaje
                : 'Este docente ya tiene otra clase que se encima.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Asignar de todas formas'),
              ),
            ],
          ),
        );
        if (confirmar != true) return;
        // Reintenta forzando.
        setState(() => _guardando = true);
        payload['forzar'] = true;
        final resp2 = await http
            .post(Uri.parse(guardianUrl),
                headers: {'Content-Type': 'text/plain;charset=utf-8'},
                body: jsonEncode(payload))
            .timeout(const Duration(seconds: 75));
        final rg2 = leerRespuesta(resp2, accion: 'asignacion_guardar_forzar');
        if (!rg2.ok) {
          throw Exception(rg2.mensaje.isNotEmpty ? rg2.mensaje : 'No se pudo guardar');
        }
        if (mounted) Navigator.pop(context, true);
        return;
      }
      // (28-sep) Choque del MISMO GRUPO: es más serio que el de docente —
      // significa que los mismos alumnos tendrían dos clases a la vez— así
      // que el backend lo trata como candado duro, no como aviso. Antes la
      // pantalla no ofrecía forma de saltarlo aunque el Guardián sí lo
      // permite con forzar=true; ahora se puede, pero con una advertencia
      // más seria que la del choque de docente, y solo a propósito.
      if (!rg.ok && rg['choque'] == true && rg['choqueDocente'] != true) {
        if (!mounted) return;
        setState(() => _guardando = false);
        final confirmar = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Choque de horario en el grupo',
                style: TextStyle(fontSize: 16)),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(rg.mensaje.isNotEmpty
                  ? rg.mensaje
                  : 'Este grupo ya tiene otra materia a esa hora.'),
              const SizedBox(height: 10),
              const Text('Esto es distinto a un choque de profesor: significa que los MISMOS alumnos '
                  'tendrían dos clases al mismo tiempo. Solo continúe si está seguro de que es correcto '
                  '(por ejemplo, al corregir un dato capturado antes).',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Asignar de todas formas'),
              ),
            ],
          ),
        );
        if (confirmar != true) return;
        setState(() => _guardando = true);
        payload['forzar'] = true;
        final resp3 = await http
            .post(Uri.parse(guardianUrl),
                headers: {'Content-Type': 'text/plain;charset=utf-8'},
                body: jsonEncode(payload))
            .timeout(const Duration(seconds: 75));
        final rg3 = leerRespuesta(resp3, accion: 'asignacion_guardar_forzar_grupo');
        if (!rg3.ok) {
          throw Exception(rg3.mensaje.isNotEmpty ? rg3.mensaje : 'No se pudo guardar');
        }
        if (mounted) Navigator.pop(context, true);
        return;
      }
      // (30-sep) ORDEN CURRICULAR: el grupo todavía no tiene registradas
      // materias de un periodo ANTERIOR del plan. Es un aviso, no un
      // bloqueo definitivo — a veces sí hay que saltarlo (p. ej. la materia
      // anterior se cursó pero nunca se le hizo su registro de asignación).
      // Mismo patrón que los choques: se pregunta y, si confirma, se
      // reintenta con forzar.
      if (!rg.ok && rg['ordenCurricular'] == true) {
        if (!mounted) return;
        setState(() => _guardando = false);
        // (2-oct) La lista llega aparte, con su semestre; si el servidor es el anterior,
        // solo trae los nombres y se agrupan bajo «Otras materias».
        final listaFaltantes = ((rg['faltantes'] as List?) ?? []).isNotEmpty
            ? (rg['faltantes'] as List)
            : ((rg['materiasFaltantes'] as List?) ?? [])
                .map((e) => {'materia': '$e', 'periodo': ''})
                .toList();
        final confirmar = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            scrollable: true,
            title: const Text('Orden curricular', style: TextStyle(fontSize: 16)),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(rg.mensaje.isNotEmpty
                  ? rg.mensaje
                  : 'Este grupo todavía no tiene registradas materias anteriores del plan.'),
              if (listaFaltantes.isNotEmpty) ...[
                const SizedBox(height: 8),
                _listaFaltantesPorPeriodo(listaFaltantes),
              ],
            ]),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Guardar de todas formas'),
              ),
            ],
          ),
        );
        if (confirmar != true) return;
        setState(() => _guardando = true);
        payload['forzar'] = true;
        final resp4 = await http
            .post(Uri.parse(guardianUrl),
                headers: {'Content-Type': 'text/plain;charset=utf-8'},
                body: jsonEncode(payload))
            .timeout(const Duration(seconds: 75));
        final rg4 = leerRespuesta(resp4, accion: 'asignacion_guardar_forzar_orden');
        if (!rg4.ok) {
          throw Exception(rg4.mensaje.isNotEmpty ? rg4.mensaje : 'No se pudo guardar');
        }
        if (mounted) Navigator.pop(context, true);
        return;
      }
      // (2-oct) MATERIA YA ASIGNADA A ESTE GRUPO. El Guardián avisa cuando el grupo ya tiene esa materia (misma generación, vigente y
      // sin invitación rechazada): antes se guardaba sin aviso, quedaba dos veces y el profesor recibía otra invitación. Si se confirma,
      // se vuelve a guardar con la bandera y pasa por los demás avisos (choques, orden curricular) como cualquier guardado.
      if (!rg.ok && rg['duplicada'] == true) {
        if (!mounted) return;
        setState(() => _guardando = false);
        final confirmar = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            scrollable: true,
            title: const Text('Materia ya asignada a este grupo', style: TextStyle(fontSize: 16)),
            content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(rg.mensaje.isNotEmpty ? rg.mensaje : 'Este grupo ya tiene esta materia asignada.'),
              const SizedBox(height: 10),
              const Text(
                  'Si guarda de todas formas, la materia quedará dos veces en el grupo y el profesor recibirá otra invitación. '
                  'Si lo que quiere es cambiar de profesor, edite la asignación existente.',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: cessumRed, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Guardar de todas formas'),
              ),
            ],
          ),
        );
        if (confirmar != true) return;
        _forzarDuplicada = true;
        await _guardar();
        return;
      }
      if (!rg.ok) {
        throw Exception(rg.mensaje.isNotEmpty ? rg.mensaje : 'No se pudo guardar');
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e, st) {
      // Solo cae aquí un fallo de RED, o el Exception que se relanzó arriba
      // ya con un mensaje humano (leerRespuesta ya reportó lo suyo; esto
      // cubre además timeout/sin conexión antes de tener respuesta).
      ErrorReporter.reportar(e, st, pantallaForzada: 'agenda:guardar');
      if (mounted) {
        setState(() => _guardando = false);
        // Muestra el motivo REAL (choque de horario, etc.), no un genérico.
        final msg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(msg.isEmpty ? 'No se pudo guardar.' : msg),
            duration: const Duration(seconds: 7)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final progs = widget.catalogo.keys.toList()..sort();
    final gensMap = (_programa != null && _programa != _kOtro)
        ? (widget.catalogo[_programa] ?? {})
        : {};
    final gensTodas = gensMap.keys.map((e) => e.toString()).toList()..sort();
    // Por defecto se ocultan las generaciones egresadas; el interruptor
    // "Mostrar generaciones egresadas" las regresa a la lista.
    final gens = _mostrarEgresados
        ? gensTodas
        : gensTodas.where((g) => !_esEgresada(g)).toList();
    final ocultas = gensTodas.length - gens.length;
    // (jul-2026) DEDUPLICACIÓN de grupos: el catálogo puede traer el mismo
    // grupo con etiqueta corta y larga a la vez ("1" y "1 - entre semana",
    // "2" y "2 - sabatino"). Se colapsan por su clave (número o 'mixta') y
    // GANA la etiqueta más descriptiva (la larga), para no sembrar
    // etiquetas inconsistentes al asignar.
    final grupos = (_programa != null &&
            _programa != _kOtro &&
            _generacion != null &&
            _generacion != _kOtro)
        ? () {
            final crudos = List<String>.from(
                widget.catalogo[_programa]?[_generacion] ?? <String>[]);
            final porClave = <String, String>{};
            for (final g in crudos) {
              final k = _claveGrupo(g);
              final actual = porClave[k];
              if (actual == null || g.trim().length > actual.trim().length) {
                porClave[k] = g;
              }
            }
            final lista = porClave.values.toList()..sort();
            return lista;
          }()
        : <String>[];

    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: Text(widget.existente == null
            ? 'Nueva asignación'
            : 'Editar asignación'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _bannerPropuesta(),
          // (23-sep) El catálogo manda: sin texto libre, salvo edición de un registro antiguo o catálogo vacío.
          _drop('Programa', _programa, progs, permitirOtro: _programa == _kOtro || progs.isEmpty, (v) {
            setState(() {
              _programa = v;
              _generacion = null;
              _grupo = null;
              _sugerirPorPrograma();
            });
            _maybeCargarAvance();
          }),
          if (_programa == _kOtro) _texto('Escribe el programa', _cProg),
          const SizedBox(height: 10),
          _drop('Generación', _generacion, gens, permitirOtro: _generacion == _kOtro || gens.isEmpty, (v) {
            setState(() {
              _generacion = v;
              _grupo = null;
            });
            _maybeCargarAvance();
          }),
          if (_generacion == _kOtro) _texto('Escribe la generación', _cGen),
          // Interruptor para ver (o volver a ocultar) las generaciones que
          // ya egresaron. Si al ocultarlas la generación elegida era una
          // egresada, se limpia la selección para no dejar un valor inválido.
          SwitchListTile(
            value: _mostrarEgresados,
            activeThumbColor: cessumGold,
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Mostrar generaciones egresadas',
                style: TextStyle(fontSize: 13)),
            subtitle: Text(
              _mostrarEgresados
                  ? 'Se muestran todas las generaciones.'
                  : ocultas > 0
                      ? '$ocultas generación(es) egresada(s) oculta(s).'
                      : 'Este programa no tiene generaciones egresadas.',
              style: const TextStyle(fontSize: 11),
            ),
            onChanged: (v) {
              setState(() {
                _mostrarEgresados = v;
                if (!v && _esEgresada(_generacion)) {
                  _generacion = null;
                  _grupo = null;
                }
              });
            },
          ),
          const SizedBox(height: 10),
          _drop('Grupo', _grupo, grupos, (v) {
            setState(() {
              _grupo = v;
              // El grupo define el tipo de sesiones y el día, así que se
              // vuelve a sugerir al elegirlo.
              _sugerirPorPrograma();
            });
            _maybeCargarAvance();
          }),
          if (_grupo == _kOtro) ...[
            _texto('Escribe el grupo', _cGrupo),
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text('Use el formato de siempre: «1 - entre semana», «2 - sabatino» o «1 - mixta».',
                  style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
            ),
          ],
          // (23-sep) Historial del grupo: qué materias y qué profesores ha tenido (solo informativo).
          if (_valProg().isNotEmpty && _valGrupo().isNotEmpty) _historialGrupoUI(),
          // (23-sep) Ver a los alumnos en cuanto hay programa elegido.
          if (_valProg().isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _verAlumnosDelCurso,
                icon: const Icon(Icons.groups_outlined, size: 18, color: cessumRed),
                label: Text(
                  _valGen().isNotEmpty && _valGrupo().isNotEmpty ? 'Ver alumnos del curso' : 'Ver alumnos del programa',
                  style: const TextStyle(color: cessumRed, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          if (_valGrupo().toLowerCase().contains('mixt')) ...[
            const SizedBox(height: 10),
            _dropFijo('Periodo', _periodo,
                const ['Verano', 'Invierno', 'Primavera'], (v) {
              setState(() => _periodo = v);
            }),
            if (_periodo != null)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(
                  _periodo == 'Verano'
                      ? 'En Verano se agendan 3 materias.'
                      : 'En ${_periodo!} se agenda 1 materia.',
                  style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFFA56B16),
                      fontWeight: FontWeight.w600),
                ),
              ),
          ],
          _panelAvance(),
          const Divider(height: 28),
          _texto('Materia', _cMateria, onCambio: (_) => setState(() {})),
          // (ago-21) AVISO CUANDO EL NOMBRE NO ESTÁ EN EL PLAN.
          //
          // El campo sigue libre a propósito: hay materias legítimas fuera
          // del plan cargado. Pero escribir a mano es como nacieron los 46
          // «TIC aplicada EN educación» contra el «TIC aplicada A LA
          // Educación» del plan —misma materia, dos nombres, y el sistema
          // viéndolas como distintas—.
          //
          // Así que no se prohíbe: se avisa. Quien escriba algo que el plan
          // no reconoce lo sabe en ese momento, no tres meses después cuando
          // sus calificaciones no cruzan.
          _avisoMateriaFueraDelPlan(),
          const SizedBox(height: 10),
          _texto('Clave de la materia', _cClave),
          const SizedBox(height: 10),
          // BLOQUE CONJUNTO — solo Mixta (excepcional): impartir varias materias
          // juntas con una invitación, un pago y una calificación.
          if (_esMixta) _bloqueConjuntoUI(),
          if (_esMixta) _gruposJuntosUI(),
          _texto('Ciclo', _cCiclo),
          const SizedBox(height: 10),
          _tipoSesionesUI(),
          if (_tipo == _kOtro) _texto('Escribe el tipo', _cTipo),
          const SizedBox(height: 10),
          if (!_esMixta) ...[
            _dropDia(),
            const SizedBox(height: 10),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F1E7),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFA56B16)),
              ),
              child: Row(
                children: const [
                  Icon(Icons.date_range, size: 18, color: Color(0xFFA56B16)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Mixta: periodo presencial intensivo (días seguidos). No se '
                      'elige un día de la semana: los días del periodo quedan '
                      'definidos por las fechas de inicio y término, que cambian '
                      'según la temporada.',
                      style: TextStyle(fontSize: 12, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
          // (25-sep) La hora también puede quedar vacía; el botón × la limpia.
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: TextField(
              controller: _cHora,
              decoration: _dec(_esMixta ? 'Horario del periodo' : 'Hora (ej. 20:00-21:00)').copyWith(
                suffixIcon: _cHora.text.trim().isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Dejar sin hora',
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => setState(() => _cHora.clear()),
                      ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (!_directo && !_esMixta)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 2),
              child: Text(
                'Puedes dejar el día y la hora vacíos: el docente los elige al aceptar la invitación.',
                style: TextStyle(fontSize: 11, color: cessumMuted(context)),
              ),
            ),
          // (15-sep) Los bloques del programa, para elegir en vez de teclear.
          // En licenciatura son los siete del sábado; en sabatino de posgrado,
          // los dos del bloque. Donde la institución no fijó horario no
          // aparece nada y el campo se escribe a mano, como siempre.
          // (15-sep) Antes se ocultaban cuando la modalidad era mixta, y
          // licenciatura ES mixta por plan de estudio: el bloque entero
          // desaparecía y quedaban los de posgrado. La licenciatura tiene día
          // y hora fijos aunque su modalidad se llame mixta.
          if ((!_esMixta || _esLicenciatura) && _bloquesHorario.isNotEmpty) ...[
            const SizedBox(height: 6),
            // (29-sep) Si la revisión de bloques no respondió, que se sepa —
            // igual que con la disponibilidad de maestros.
            if (_bloquesFallo)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '⚠ No se pudo revisar qué bloques ya están ocupados. Ninguno aparece '
                  'ocupado, pero puede haber choque: se validará al guardar.',
                  style: TextStyle(fontSize: 11.5, color: Colors.orange.shade800, fontWeight: FontWeight.w600),
                ),
              ),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Bloques:', style: TextStyle(fontSize: 12)),
                ..._bloquesHorario.map((h) {
                  final ocupado = _bloquesVerificados &&
                      _bloqueOcupadoPor.containsKey(h);
                  final que = _bloqueOcupaQue[h] ?? '';
                  final hasta = _bloqueOcupaHasta[h] ?? '';
                  final texto = ocupado
                      ? '$h · ocupado${que.isNotEmpty ? ': $que' : ''}'
                          '${hasta.isNotEmpty ? ' · hasta $hasta' : ''}'
                      : h;
                  return ChoiceChip(
                    label: Text(
                      texto,
                      style: TextStyle(
                        fontSize: 11,
                        color: ocupado ? cessumMuted(context) : null,
                      ),
                    ),
                    selected: _cHora.text.trim().replaceAll(' ', '') ==
                        h.replaceAll(' ', ''),
                    selectedColor: cessumRed.withValues(alpha: 0.15),
                    // (29-sep) Igual que con el maestro: el bloque ocupado no
                    // se esconde, queda visible con el motivo, y se puede
                    // elegir igual — el choque real se valida al guardar.
                    onSelected: (_) => setState(() => _cHora.text = h),
                  );
                }),
              ],
            ),
            // (30-sep) El bloque anterior del grupo, para dar contexto de
            // dónde viene el bloque vigente que se está llenando.
            // (2-oct-2026) Una línea por materia —franja · materia · profesor— y
            // las reconstruidas, marcadas «aprox.»: su horario y sus fechas no
            // son datos firmes y no deben leerse como tales.
            if (_bloquesVerificados && _bloqueAnterior.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _bloqueAnteriorInicio.isNotEmpty && _bloqueAnteriorTermino.isNotEmpty
                          ? 'Bloque anterior · del $_bloqueAnteriorInicio al $_bloqueAnteriorTermino'
                          : 'Bloque anterior',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: cessumMuted(context)),
                    ),
                    const SizedBox(height: 2),
                    for (final b in _bloqueAnterior)
                      Text(
                        '${b['hora'] ?? ''} · ${b['materia'] ?? ''}'
                        '${'${b['docente'] ?? ''}'.isNotEmpty ? ' · ${b['docente']}' : ''}'
                        '${b['aproximada'] == true ? '  (aprox.)' : ''}',
                        style: TextStyle(fontSize: 11, color: cessumMuted(context)),
                      ),
                    if (_bloqueAnterior.any((b) => b['aproximada'] == true))
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '«aprox.»: asignación reconstruida; su horario y sus fechas son aproximados.',
                          style: TextStyle(
                              fontSize: 10.5,
                              fontStyle: FontStyle.italic,
                              color: cessumMuted(context)),
                        ),
                      ),
                  ],
                ),
              ),
          ],
          const Divider(height: 28),
          _selectorMaestro(),
          const Divider(height: 28),
          if (!_esMixta) _panelFechasAuto(),
          _texto('Inicio (AAAA-MM-DD)', _cInicio,
              onCambio: _refrescarDispSiFechaCompleta),
          const SizedBox(height: 10),
          _texto('Término (AAAA-MM-DD)', _cTermino,
              onCambio: _refrescarDispSiFechaCompleta),
          if (!_esMixta) ...[
            const SizedBox(height: 8),
            _vistaPreviaSesiones(),
          ],
          const Divider(height: 28),
          _texto('Link de la videollamada', _cLlamada),
          const SizedBox(height: 10),
          _texto('Link del Aula CESSUM', _cAula),
          const SizedBox(height: 10),
          _texto('Notas (opcional)', _cNotas),
          const SizedBox(height: 12),
          SwitchListTile(
            value: _activa,
            activeThumbColor: cessumRed,
            contentPadding: EdgeInsets.zero,
            title: const Text('Asignación activa'),
            subtitle: const Text(
                'Si está activa, el maestro la verá en "Mis materias".'),
            onChanged: (v) => setState(() => _activa = v),
          ),
          SwitchListTile(
            value: _directo,
            activeThumbColor: cessumRed,
            contentPadding: EdgeInsets.zero,
            title: const Text('Asignar directo (sin invitación)'),
            subtitle: const Text(
                'Queda aceptada de inmediato con el día y la hora que pongas. '
                'No se envía invitación al maestro (requiere día y hora).'),
            onChanged: (v) => setState(() {
              _directo = v;
              if (v) _prospectivo = false; // no pueden estar ambos a la vez
            }),
          ),
          // Modo prospectivo: agendar a futuro (siguiente periodo/materia).
          SwitchListTile(
            value: _prospectivo,
            activeThumbColor: const Color(0xFF6A1B9A),
            contentPadding: EdgeInsets.zero,
            title: const Text('Agendar a futuro (siguiente periodo/materia)'),
            subtitle: const Text(
                'Se envía la invitación desde ahora y la materia queda ACTIVA; '
                'las fechas futuras marcan cuándo inicia. El sistema sugiere materia y docente.'),
            onChanged: (v) => setState(() {
              _prospectivo = v;
              if (v) _directo = false; // no pueden estar ambos a la vez
              if (!v) _materiasSugeridas = [];
            }),
          ),
          if (_prospectivo) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF6A1B9A).withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF6A1B9A).withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome,
                          color: Color(0xFF6A1B9A), size: 18),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text('Sugerencias del siguiente periodo',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                      TextButton(
                        onPressed:
                            _cargandoSugerencias ? null : _cargarSugerencias,
                        child: _cargandoSugerencias
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Ver sugerencias'),
                      ),
                    ],
                  ),
                  if (_materiasSugeridas.isNotEmpty)
                    ..._materiasSugeridas.map((mat) {
                      final docs =
                          (mat['docentesSugeridos'] as List?) ?? [];
                      final Map<String, dynamic>? mejorDoc = docs.isNotEmpty
                          ? Map<String, dynamic>.from(docs.first as Map)
                          : null;
                      return Card(
                        margin: const EdgeInsets.only(top: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${mat['materia']}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                              if ((mat['periodo'] ?? '')
                                  .toString()
                                  .isNotEmpty)
                                Text('Periodo: ${mat['periodo']}',
                                    style: TextStyle(
                                        fontSize: 11.5,
                                        color: cessumMuted(context))),
                              if (mejorDoc != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    'Docente sugerido: ${mejorDoc['nombre']} — ${mejorDoc['motivo']}',
                                    style: const TextStyle(
                                        fontSize: 11.5,
                                        color: Color(0xFF6A1B9A)),
                                  ),
                                )
                              else
                                Padding(
                                  padding: EdgeInsets.only(top: 4),
                                  child: Text('Sin docente sugerido',
                                      style: TextStyle(
                                          fontSize: 11.5,
                                          color: cessumFaint(context))),
                                ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: () =>
                                      _aplicarSugerencia(mat, mejorDoc),
                                  icon: const Icon(Icons.check, size: 16),
                                  label: const Text('Usar esta'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _guardando ? null : () => _guardar(),
              icon: _guardando
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save),
              label: Text(_guardando ? 'Guardando...' : 'Guardar'),
            ),
          ),
          // (23-sep) Revisar antes de guardar, con las reglas del Guardián.
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: cessumRed,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: _guardando ? null : () => _guardar(soloValidar: true),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Revisar con el Guardián, sin guardar'),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _drop(String label, String? value, List<String> opciones,
      ValueChanged<String?> onChanged, {bool permitirOtro = true}) {
    // (23-sep) Más de 8 opciones: campo con buscador en lugar de lista plana.
    if (opciones.length > 8) {
      final texto = value == null ? '' : (value == _kOtro ? 'Otro…' : value);
      return InkWell(
        onTap: () async {
          final elegido = await _elegirConBusqueda(label.toLowerCase(), opciones, permitirOtro: permitirOtro);
          if (elegido != null) onChanged(elegido);
        },
        child: InputDecorator(
          decoration: _dec(label).copyWith(suffixIcon: const Icon(Icons.search)),
          isEmpty: texto.isEmpty,
          child: Text(texto, overflow: TextOverflow.ellipsis),
        ),
      );
    }
    final items = <DropdownMenuItem<String>>[
      ...opciones.map((o) =>
          DropdownMenuItem<String>(value: o, child: Text(o, overflow: TextOverflow.ellipsis))),
      // (23-sep) «Otro» solo donde se permite (ver _drop de Programa y Generación).
      if (permitirOtro) const DropdownMenuItem<String>(value: _kOtro, child: Text('Otro…')),
    ];
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: _dec(label),
      items: items,
      onChanged: onChanged,
    );
  }

  Widget _dropFijo(String label, String? value, List<String> opciones,
      ValueChanged<String?> onChanged) {
    return _drop(label, value, opciones, onChanged);
  }

  /// (22-sep) Tipo de sesiones: cada opción dice qué significa. En la lista
  /// se ve el título con su explicación; ya elegida, solo el título.
  void _alCambiarTipo(String? v) {
    setState(() {
      _tipo = v;
      _tipoManual = true;
      // Mixta no lleva día de la semana; el tipo y el día no se contradicen.
      if (_esMixta) _dia = null;
      if (v == 'Sabatino') _dia = 'Sábado';
      if (v == 'Entre semana' && (_dia == 'Sábado' || _dia == 'Domingo')) _dia = null;
    });
    _cargarDisponibilidad();
    _cargarBloquesGrupo();
  }

  void _volverAlDelGrupo(String t) {
    setState(() {
      _tipoManual = false;
      _tipo = t;
      if (t == 'Mixto') _dia = null;
      if (t == 'Sabatino') _dia = 'Sábado';
      if (t == 'Entre semana' && (_dia == 'Sábado' || _dia == 'Domingo')) _dia = null;
    });
    _cargarDisponibilidad();
    _cargarBloquesGrupo();
  }

  /// (22-sep) Tipo de sesiones tomado del grupo. Se muestra como dato, con
  /// «Cambiar» para un caso excepcional; si el grupo no lo dice, se elige.
  Widget _tipoSesionesUI() {
    final delGrupo = _tipoDelGrupo();
    final hint = Theme.of(context).hintColor;
    if (_tipoManual || delGrupo == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dropTipo(_alCambiarTipo),
          if (delGrupo != null && _tipo != delGrupo)
            TextButton.icon(
              onPressed: () => _volverAlDelGrupo(delGrupo),
              icon: const Icon(Icons.undo, size: 16),
              label: Text('Usar el del grupo: ${_tituloTipo(delGrupo)}'),
            ),
        ],
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Icon(_iconoTipo(delGrupo), color: cessumRed),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tipo de sesiones', style: TextStyle(fontSize: 11, color: hint)),
                Text(_tituloTipo(delGrupo),
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                Text(_detalleTipo(delGrupo),
                    style: TextStyle(fontSize: 12, color: hint, height: 1.3)),
                Text('Se toma del grupo «${_valGrupo()}».',
                    style: TextStyle(fontSize: 11, color: hint, height: 1.3)),
              ],
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _tipoManual = true),
            child: const Text('Cambiar'),
          ),
        ],
      ),
    );
  }

  Widget _dropTipo(ValueChanged<String?> onChanged) {
    final valores = [..._tipos, _kOtro];
    return DropdownButtonFormField<String>(
      value: _tipo,
      isExpanded: true,
      itemHeight: 56,
      decoration: _dec('Tipo de sesiones'),
      selectedItemBuilder: (_) => valores
          .map((v) => Align(
                alignment: Alignment.centerLeft,
                child: Text(v == _kOtro ? 'Otro…' : _tituloTipo(v),
                    overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      items: valores
          .map((v) => DropdownMenuItem<String>(
                value: v,
                child: v == _kOtro
                    ? const Text('Otro…')
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_tituloTipo(v),
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(_detalleTipo(v),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11.5, color: cessumMuted(context))),
                        ],
                      ),
              ))
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _dropDia() {
    // (25-sep) SE PUEDE DEJAR SIN DÍA. En los programas sin horario fijo el
    // docente elige el día al aceptar la invitación; el selector no tenía
    // forma de quitar el día (que además se llena solo con el de la materia
    // anterior del grupo). La opción vacía deja _dia en null.
    final valorDia = (_dia != null && _dias.contains(_dia)) ? _dia : '';
    return DropdownButtonFormField<String>(
      value: valorDia,
      isExpanded: true,
      decoration: _dec('Día'),
      items: [
        const DropdownMenuItem<String>(
            value: '',
            child: Text('Sin día · lo elige el docente',
                style: TextStyle(fontStyle: FontStyle.italic))),
        ..._dias.map((d) => DropdownMenuItem<String>(value: d, child: Text(d))),
      ],
      onChanged: (v) {
        setState(() {
          _dia = (v == null || v.isEmpty) ? null : v;
          // (22-sep) Si el día contradice el tipo, manda el día: es el dato
          // que se ve en el calendario. Mixta y «Otro» no se tocan.
          if (v == 'Sábado' && _tipo == 'Entre semana') _tipo = 'Sabatino';
          if (v != null && v != 'Sábado' && v != 'Domingo' && _tipo == 'Sabatino') {
            _tipo = 'Entre semana';
          }
        });
        _cargarDisponibilidad();
        _cargarBloquesGrupo();
      },
    );
  }

  void _onHoraCambio() {
    final h = _cHora.text.trim();
    if (RegExp(r'\d{1,2}[:.]\d{2}.*[-a].*\d').hasMatch(h)) {
      _cargarDisponibilidad();
    }
  }

  Future<void> _cargarDisponibilidad() async {
    final dia = _dia ?? '';
    final hora = _cHora.text.trim();
    if (dia.isEmpty || hora.isEmpty) {
      _dispVerificada = false;
      _dispFallo = false;
      if (mounted) {
        setState(() {
          _ocupados.clear();
          _conflicto.clear();
          _dispFiltrado = false;
        });
      }
      return;
    }
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'maestros_disponibles',
        'dia': dia,
        'hora': hora,
        // Vigencia de la materia que se agenda: con esto el backend solo
        // marca ocupado a un maestro si los PERIODOS se traslapan (misma
        // hora en fechas distintas no es choque).
        'inicio': _cInicio.text.trim(),
        'termino': _cTermino.text.trim(),
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 45));
      final r = leerRespuesta(resp, accion: 'maestros_disponibles');
      if (!r.ok) {
        _dispVerificada = false;
        _dispFallo = true;
        if (mounted) setState(() {});
        return;
      }
      final data = r.datos;
      final nuevos = <String>{};
      final conf = <String, String>{};
      for (final raw in (data['maestros'] as List<dynamic>? ?? [])) {
        final m = Map<String, dynamic>.from(raw as Map);
        if (m['disponible'] != true) {
          final c = (m['correo'] ?? '').toString().toLowerCase();
          nuevos.add(c);
          conf[c] = (m['conflicto'] ?? '').toString();
        }
      }
      if (!mounted) return;
      setState(() {
        _ocupados
          ..clear()
          ..addAll(nuevos);
        _conflicto
          ..clear()
          ..addAll(conf);
        _dispFiltrado = data['filtrado'] == true;
        // Antes se limpiaba el maestro elegido si aparecía "ocupado", lo que
        // borraba selecciones válidas (maestros nuevos). Ya NO se limpia:
        // el maestro elegido se conserva y sigue visible en la lista.
        // (El choque real de horario se valida aparte al guardar.)
        _dispVerificada = true;
        _dispFallo = false;
      });
    } catch (e, s) {
      // (23-sep) Ya no se traga: sin respuesta, nadie aparece ocupado y hay
      // que decirlo. (28-sep, Fase 3) Y ahora también queda registrado.
      ErrorReporter.reportar(e, s, pantallaForzada: 'agenda:maestros_disponibles');
      _dispVerificada = false;
      _dispFallo = true;
      if (mounted) setState(() {});
    }
  }

  // (29-sep) Consulta cuál de los bloques fijos (los 2 del sabatino de
  // posgrado, los 7 de licenciatura) ya está ocupado — por el GRUPO o por
  // el maestro que se está eligiendo — y por qué. Se llama junto con
  // _cargarDisponibilidad: mismos disparadores, misma idea (marcar, no
  // esconder). Si el programa no tiene bloques fijos (_bloquesHorario
  // vacío) no hay nada que consultar.
  Future<void> _cargarBloquesGrupo() async {
    if (_bloquesHorario.isEmpty ||
        _valProg().isEmpty || _valGen().isEmpty || _valGrupo().isEmpty) {
      _bloquesVerificados = false;
      _bloquesFallo = false;
      if (mounted) {
        setState(() {
          _bloqueOcupadoPor.clear();
          _bloqueOcupaQue.clear();
          _bloqueOcupaHasta.clear();
          _bloqueAnterior = [];
          _bloqueAnteriorInicio = '';
          _bloqueAnteriorTermino = '';
        });
      }
      return;
    }
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'horarios_sabatino',
        'programa': _valProg(),
        'generacion': _valGen(),
        'grupo': _valGrupo(),
        if (_dia != null) 'dia': _dia!,
        if (_cCorreo.text.trim().isNotEmpty) 'correoDocente': _cCorreo.text.trim(),
        // (30-sep) Sin esto el backend no podía saber qué periodo se está
        // proponiendo y marcaba ocupado cualquier materia ya terminada.
        if (_cInicio.text.trim().isNotEmpty) 'fechaInicio': _cInicio.text.trim(),
        if (_cTermino.text.trim().isNotEmpty) 'fechaTermino': _cTermino.text.trim(),
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final r = leerRespuesta(resp, accion: 'horarios_sabatino');
      if (!r.ok) {
        _bloquesVerificados = false;
        _bloquesFallo = true;
        if (mounted) setState(() {});
        return;
      }
      final nuevosPor = <String, String>{};
      final nuevosQue = <String, String>{};
      final nuevosHasta = <String, String>{};
      for (final raw in (r.datos['bloques'] as List<dynamic>? ?? [])) {
        final b = Map<String, dynamic>.from(raw as Map);
        if (b['libre'] != true) {
          // El backend habla en "HH:MM a HH:MM"; los bloques de esta
          // pantalla, en "HH:MM - HH:MM". Se normaliza aquí para que el
          // lookup por texto (más abajo, en el Wrap de chips) coincida.
          final h = (b['hora'] ?? '').toString().replaceAll(' a ', ' - ');
          nuevosPor[h] = (b['ocupadoPor'] ?? '').toString();
          nuevosQue[h] = (b['ocupaQue'] ?? '').toString();
          nuevosHasta[h] = (b['ocupaHasta'] ?? '').toString();
        }
      }
      final nuevoAnterior = ((r.datos['bloqueAnterior'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _bloqueOcupadoPor
          ..clear()
          ..addAll(nuevosPor);
        _bloqueOcupaQue
          ..clear()
          ..addAll(nuevosQue);
        _bloqueOcupaHasta
          ..clear()
          ..addAll(nuevosHasta);
        _bloqueAnterior = nuevoAnterior;
        // (2-oct) El servidor ya manda el rango del bloque solo con el día. Con un
        // servidor anterior a este cambio no lo manda: se cae a la primera fila.
        _bloqueAnteriorInicio = '${r.datos['bloqueAnteriorInicio'] ?? ''}'.trim();
        _bloqueAnteriorTermino = '${r.datos['bloqueAnteriorTermino'] ?? ''}'.trim();
        if (nuevoAnterior.isNotEmpty) {
          if (_bloqueAnteriorInicio.isEmpty) _bloqueAnteriorInicio = '${nuevoAnterior.first['inicio'] ?? ''}'.trim();
          if (_bloqueAnteriorTermino.isEmpty) _bloqueAnteriorTermino = '${nuevoAnterior.first['termino'] ?? ''}'.trim();
        }
        _bloquesVerificados = true;
        _bloquesFallo = false;
      });
    } catch (e, s) {
      ErrorReporter.reportar(e, s, pantallaForzada: 'agenda:horarios_sabatino');
      _bloquesVerificados = false;
      _bloquesFallo = true;
      if (mounted) setState(() {});
    }
  }

  // (29-sep) Trae el horario actual del maestro elegido — todas sus
  // asignaciones activas y vigentes, agrupadas por día — para decidir a
  // qué hora ponerlo en esta asignación directa sin adivinar ni tener que
  // consultarlo aparte.
  Future<void> _cargarHorarioMaestro(String correo) async {
    if (correo.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _horarioMaestro = [];
          _horarioMaestroNombre = '';
          _horarioMaestroFallo = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _horarioMaestroCargando = true);
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'horario_docente_actual',
        'correo': correo.trim(),
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final r = leerRespuesta(resp, accion: 'horario_docente_actual');
      if (!mounted) return;
      if (!r.ok) {
        setState(() {
          _horarioMaestroFallo = true;
          _horarioMaestroCargando = false;
        });
        return;
      }
      final lista = ((r.datos['horario'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        _horarioMaestro = lista;
        _horarioMaestroNombre = (r.datos['nombreDocente'] ?? '').toString();
        _horarioMaestroFallo = false;
        _horarioMaestroCargando = false;
      });
    } catch (e, s) {
      ErrorReporter.reportar(e, s, pantallaForzada: 'agenda:horario_docente_actual');
      if (!mounted) return;
      setState(() {
        _horarioMaestroFallo = true;
        _horarioMaestroCargando = false;
      });
    }
  }

  // Tarjeta asistiva con el horario del maestro elegido: agrupado por día,
  // con el bloque que se está por asignar resaltado si coincide (choque
  // a la vista, antes de guardar).
  Widget _tarjetaHorarioMaestro() {
    if (_horarioMaestroCargando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          SizedBox(
              width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 8),
          Text('Cargando su horario actual…', style: TextStyle(fontSize: 12)),
        ]),
      );
    }
    if (_horarioMaestroFallo) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          '⚠ No se pudo cargar el horario actual de este maestro. Revísalo aparte antes de asignar.',
          style: TextStyle(fontSize: 11.5, color: Colors.orange.shade800, fontWeight: FontWeight.w600),
        ),
      );
    }
    if (_horarioMaestroNombre.isEmpty && _horarioMaestro.isEmpty) {
      return const SizedBox.shrink();
    }
    final horaSel = _cHora.text.trim().replaceAll(' ', '');
    final diaSel = _dia ?? '';
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cessumRed.withValues(alpha: 0.04),
        border: Border.all(color: cessumRed.withValues(alpha: 0.15)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _horarioMaestro.isEmpty
                ? 'Horario actual de $_horarioMaestroNombre: sin materias activas ahora mismo.'
                : 'Horario actual de $_horarioMaestroNombre:',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          if (_horarioMaestro.isNotEmpty) const SizedBox(height: 4),
          ..._horarioMaestro.map((h) {
            final dia = (h['dia'] ?? '').toString();
            final hora = (h['hora'] ?? '').toString();
            final coincideDia = diaSel.isNotEmpty &&
                dia.toLowerCase() == diaSel.toLowerCase();
            final coincideHora = horaSel.isNotEmpty &&
                hora.replaceAll(' ', '') == horaSel;
            final chocaConEstaAsignacion = coincideDia && coincideHora;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 1.5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    chocaConEstaAsignacion ? Icons.error : Icons.circle,
                    size: chocaConEstaAsignacion ? 14 : 6,
                    color: chocaConEstaAsignacion ? Colors.red.shade700 : cessumMuted(context),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '$dia $hora · ${h['materia']} (${h['programa']} ${h['generacion']} ${h['grupo']})',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: chocaConEstaAsignacion ? FontWeight.w700 : FontWeight.normal,
                        color: chocaConEstaAsignacion ? Colors.red.shade700 : null,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          if (_horarioMaestro.any((h) {
            final dia = (h['dia'] ?? '').toString();
            final hora = (h['hora'] ?? '').toString();
            return diaSel.isNotEmpty && dia.toLowerCase() == diaSel.toLowerCase() &&
                horaSel.isNotEmpty && hora.replaceAll(' ', '') == horaSel;
          }))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Ese día y hora ya los tiene ocupados — elige otro bloque.',
                style: TextStyle(fontSize: 11, color: Colors.red.shade700, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }

  // ===================================================================
  //  FECHAS AUTOMÁTICAS (jul-2026). Reglas institucionales:
  //  · Semanas por tipo: sabatino 10 · entre semana 5 · M. en Educación 4
  //  · El inicio SIEMPRE es lunes; el término SIEMPRE es el domingo de la
  //    última semana (inicio + semanas*7 - 1).
  //  · Receso entre materias: 10 sem → 2 semanas; entre semana → 1 semana
  //    (reanuda el lunes posterior al descanso); M. en Educación → 0
  //    (continua: el lunes inmediato al domingo de término).
  //  · El rango SUGERIDO parte del último término del grupo + receso.
  //  · La edición manual de los campos sigue disponible.
  // ===================================================================
  // Clave de grupo para deduplicar etiquetas ("1" ≡ "1 - entre semana").
  String _claveGrupo(String g) {
    final t = g.trim().toLowerCase();
    if (t.contains('mixt')) return 'mixta';
    final m = RegExp(r'^(\d+)').firstMatch(t);
    return m != null ? m.group(1)! : t;
  }

  // (2-oct-2026) UNA SOLA LECTURA DE FECHAS, Y TOLERANTE.
  // Las asignaciones se guardan con la fecha en DOS formatos: «2026-09-28» (la
  // que escribe este formulario) y «28/09/2026» (la que escribe el diálogo de
  // Editar de la pantalla, que convierte a dd/mm/aaaa para mostrarla).
  // _fechaIsoTexto solo entiende el primero, así que toda asignación editada a
  // mano DESAPARECÍA del historial del grupo: el «Sugerido» no la veía, la
  // propuesta automática tampoco, y el término no se recalculaba. El grupo
  // quedaba sin sugerencia y el lunes de inicio se elegía a ciegas. Es una de
  // las vías que dejaron a Diversidad y Aprendizaje Inclusivo (MENE 26-3 SAB)
  // una semana corrida (arrancó el 10 de octubre en vez del 3). OJO: la causa
  // exacta de ese caso no se pudo confirmar contra la hoja de asignaciones; lo
  // comprobado es que esta lectura ignoraba dd/mm/aaaa y que el selector de
  // lunes arrancaba en «el próximo lunes de hoy», no en el del grupo.
  DateTime? _fechaIso(String s) {
    final t = s.trim().replaceAll(RegExp(r'[\u2010\u2011\u2012\u2013\u2014]'), '-');
    if (t.isEmpty) return null;
    final iso = _fechaIsoTexto(t);
    if (iso != null) return iso;
    final dmy = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4})').firstMatch(t);
    if (dmy != null) {
      return _fechaValida(int.parse(dmy.group(3)!), int.parse(dmy.group(2)!),
          int.parse(dmy.group(1)!));
    }
    // Texto largo de JavaScript: «Sun Oct 04 2026 00:00:00 GMT-0700 (…)».
    final largo =
        RegExp(r'^[A-Za-z]{3},?\s+([A-Za-z]{3})\s+(\d{1,2})\s+(\d{4})').firstMatch(t);
    if (largo != null) {
      const meses = <String, int>{
        'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
        'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
      };
      final mo = meses[largo.group(1)!.toLowerCase()];
      if (mo != null) {
        return _fechaValida(int.parse(largo.group(3)!), mo, int.parse(largo.group(2)!));
      }
    }
    return null;
  }

  // 31/04 no existe: DateTime lo desbordaría a 1 de mayo sin avisar.
  DateTime? _fechaValida(int y, int mo, int d) {
    if (y < 1900 || mo < 1 || mo > 12 || d < 1 || d > 31) return null;
    final f = DateTime(y, mo, d);
    return f.month == mo ? f : null;
  }

  // ── Aritmética de fechas sin horas (no se rompe con cambios de horario) ──
  DateTime _soloDia(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _sumaDias(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);
  int _diasEntre(DateTime a, DateTime b) =>
      DateTime.utc(b.year, b.month, b.day)
          .difference(DateTime.utc(a.year, a.month, a.day))
          .inDays;
  DateTime _lunesDe(DateTime d) {
    var x = _soloDia(d);
    while (x.weekday != DateTime.monday) {
      x = _sumaDias(x, -1);
    }
    return x;
  }

  int? _weekdayDeDia(String? dia) {
    const mapa = <String, int>{
      'lunes': 1, 'martes': 2, 'miercoles': 3, 'jueves': 4,
      'viernes': 5, 'sabado': 6, 'domingo': 7,
    };
    return mapa[_normaPrograma(dia ?? '')];
  }

  static const List<String> _nomDiasCorto = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
  static const List<String> _nomMesesCorto = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
  ];
  String _fechaDiaTxt(DateTime d) =>
      '${_nomDiasCorto[d.weekday - 1]} ${d.day} ${_nomMesesCorto[d.month - 1]}';
  String _diaMesTxt(DateTime d) => '${d.day} ${_nomMesesCorto[d.month - 1]}';

  /// Las sesiones que caen entre inicio y término: el primer día de clase en o
  /// después del inicio (contando ese mismo día) y de ahí cada 7 días. Es la
  /// MISMA cuenta que hace el Guardián al crear la serie en Calendar.
  List<DateTime> _fechasDeSesiones(DateTime ini, DateTime fin, int weekday) {
    var d = _soloDia(ini);
    var guarda = 0;
    while (d.weekday != weekday && guarda < 7) {
      d = _sumaDias(d, 1);
      guarda++;
    }
    final out = <DateTime>[];
    while (!d.isAfter(fin) && out.length < 60) {
      out.add(d);
      d = _sumaDias(d, 7);
    }
    return out;
  }

  /// La fila que se está editando no cuenta como «materia anterior» de sí misma.
  bool _esLaEditada(Map<String, dynamic> a) {
    final fila = widget.existente == null ? null : widget.existente!['fila'];
    if (fila == null) return false;
    return '${a['fila'] ?? ''}' == '$fila';
  }

  /// (2-oct-2026) Lo que el formulario sabe y quien captura no ve: si las
  /// fechas escritas dejan un hueco o un salto frente a la materia anterior del
  /// grupo, o si la misma materia arranca otra semana en un grupo hermano.
  /// Son avisos, no candados: puede haber razón para cualquiera de los dos.
  List<_AvisoFecha> _avisosDeFechas() {
    final out = <_AvisoFecha>[];
    if (_esMixta) return out;
    final ini = _fechaIso(_cInicio.text.trim());
    final fin = _fechaIso(_cTermino.text.trim());
    if (ini == null || fin == null) return out;
    if (fin.isBefore(ini)) {
      out.add(const _AvisoFecha('El término es anterior al inicio.', true));
      return out;
    }
    final prog = _valProg().trim();
    final gen = _valGen().trim();
    final gr = _valGrupo().trim();
    final esEd = widget.existente != null && widget.existente!['fila'] != null;
    final hoy = _soloDia(DateTime.now());

    // 1) Las sesiones que caen entre las fechas, según el día.
    final wd = _weekdayDeDia(_dia);
    if (wd != null) {
      final ses = _fechasDeSesiones(ini, fin, wd);
      if (ses.isEmpty) {
        out.add(_AvisoFecha(
            'Entre esas fechas no cae ningún ${(_dia ?? '').toLowerCase()}: no se crearía ninguna sesión.',
            true));
      } else {
        if (!_esLicenciatura && ses.length != _semanas) {
          out.add(_AvisoFecha(
              'Con estas fechas caen ${ses.length} sesión(es) y este programa define $_semanas. Revisa el inicio y el término.',
              false));
        }
        if (!esEd && ses.first.isBefore(hoy)) {
          out.add(_AvisoFecha(
              'La primera sesión (${_fechaDiaTxt(ses.first)}) ya pasó.', false));
        }
      }
    }
    if (!_esLicenciatura && ini.weekday != DateTime.monday) {
      out.add(_AvisoFecha(
          'El inicio cae en ${_fechaDiaTxt(ini)}; las fechas automáticas parten del lunes de la semana.',
          false));
    }

    // 2) Continuidad con la materia anterior del MISMO grupo. Se omite en
    //    licenciatura (las materias corren en paralelo) y en sabatino de
    //    posgrado de dos franjas (dos materias por bloque).
    final encadena = !_esLicenciatura &&
        _bloquesHorario.length != 2 &&
        prog.isNotEmpty &&
        gr.isNotEmpty;
    final matN = _normaPrograma(_cMateria.text);
    if (encadena) {
      Map<String, dynamic>? ant;
      DateTime? finAnt;
      for (final a in widget.asignaciones) {
        if (_esLaEditada(a)) continue;
        if (_normaPrograma('${a['programa'] ?? ''}') != _normaPrograma(prog)) continue;
        if ('${a['generacion'] ?? ''}'.trim() != gen) continue;
        if ('${a['grupo'] ?? ''}'.trim() != gr) continue;
        if (matN.isNotEmpty && _normaPrograma('${a['materia'] ?? ''}') == matN) continue;
        final f = _fechaIso('${a['termino'] ?? ''}');
        if (f == null || !f.isBefore(ini)) continue;
        if (finAnt == null || f.isAfter(finAnt)) {
          finAnt = f;
          ant = a;
        }
      }
      if (ant != null && finAnt != null) {
        var esperado = _sumaDias(finAnt, 1 + _recesoSemanas * 7);
        while (esperado.weekday != DateTime.monday) {
          esperado = _sumaDias(esperado, 1);
        }
        final lunesIni = _lunesDe(ini);
        final difSem = _diasEntre(esperado, lunesIni) ~/ 7;
        final nomAnt = '${ant['materia'] ?? 'la materia anterior'}';
        final receso = _recesoSemanas == 0
            ? ''
            : ' (con $_recesoSemanas semana(s) de receso)';
        if (difSem > 0) {
          final cuanto = difSem == 1 ? 'una semana' : '$difSem semanas';
          out.add(_AvisoFecha(
              'Se salta $cuanto: «$nomAnt» termina el ${_fechaDiaTxt(finAnt)}$receso, así que esta debería empezar el lunes ${_diaMesTxt(esperado)} y empieza el lunes ${_diaMesTxt(lunesIni)}.',
              false));
        } else if (difSem < 0) {
          out.add(_AvisoFecha(
              'Empieza antes de lo previsto: «$nomAnt» termina el ${_fechaDiaTxt(finAnt)}$receso, y lo normal es empezar el lunes ${_diaMesTxt(esperado)}.',
              false));
        }
      }
    }

    // 3) La MISMA materia en otro grupo de la misma generación: si dura lo
    //    mismo, lo normal es que arranque la misma semana.
    if (matN.isNotEmpty && prog.isNotEmpty && gen.isNotEmpty) {
      final spanPropio = _diasEntre(ini, fin);
      final vistos = <String>{};
      for (final a in widget.asignaciones) {
        if (_esLaEditada(a)) continue;
        if (_normaPrograma('${a['programa'] ?? ''}') != _normaPrograma(prog)) continue;
        if ('${a['generacion'] ?? ''}'.trim() != gen) continue;
        if (_normaPrograma('${a['materia'] ?? ''}') != matN) continue;
        final g = '${a['grupo'] ?? ''}'.trim();
        if (g.isEmpty || g == gr) continue;
        final ai = _fechaIso('${a['inicio'] ?? ''}');
        final af = _fechaIso('${a['termino'] ?? ''}');
        if (ai == null || af == null) continue;
        if (_diasEntre(ai, af) != spanPropio) continue; // otra duración: no es comparable
        final lunesOtro = _lunesDe(ai);
        final lunesMio = _lunesDe(ini);
        if (_diasEntre(lunesOtro, lunesMio) == 0 || !vistos.add(g)) continue;
        out.add(_AvisoFecha(
            'Esta misma materia en «$g» arranca la semana del lunes ${_diaMesTxt(lunesOtro)}; aquí, la del lunes ${_diaMesTxt(lunesMio)}. ¿Es intencional?',
            false));
      }
    }
    return out;
  }

  /// Vista previa de lo que se va a crear: las sesiones reales y los avisos.
  Widget _vistaPreviaSesiones() {
    return AnimatedBuilder(
      animation: Listenable.merge([_cInicio, _cTermino, _cHora, _cMateria]),
      builder: (ctx, _) {
        final ini = _fechaIso(_cInicio.text.trim());
        final fin = _fechaIso(_cTermino.text.trim());
        if (ini == null || fin == null) return const SizedBox.shrink();
        final avisos = _avisosDeFechas();
        final wd = _weekdayDeDia(_dia);
        final ses = (wd == null || fin.isBefore(ini))
            ? <DateTime>[]
            : _fechasDeSesiones(ini, fin, wd);
        final hayGrave = avisos.any((a) => a.grave);
        final color = hayGrave
            ? const Color(0xFFC62828)
            : (avisos.isNotEmpty ? const Color(0xFFB26A00) : const Color(0xFF2E7D32));
        final hora = _cHora.text.trim();
        return Container(
          margin: const EdgeInsets.only(top: 2, bottom: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(
                    hayGrave
                        ? Icons.error_outline
                        : (avisos.isNotEmpty
                            ? Icons.warning_amber_rounded
                            : Icons.event_available),
                    size: 18,
                    color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    wd == null
                        ? 'Sin día elegido: las sesiones se calculan cuando el docente elige día.'
                        : 'Sesiones que se crearán: ${ses.length}${hora.isEmpty ? '' : ' · $hora'}',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 12.5, color: color),
                  ),
                ),
              ]),
              if (ses.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (var i = 0; i < ses.length; i++)
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: i == 0 ? color.withValues(alpha: 0.15) : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: color.withValues(alpha: 0.35)),
                        ),
                        child: Text(
                          i == 0
                              ? 'Primera · ${_fechaDiaTxt(ses[i])}'
                              : _fechaDiaTxt(ses[i]),
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: i == 0 ? FontWeight.w800 : FontWeight.w500,
                              color: Colors.black87),
                        ),
                      ),
                  ],
                ),
              ],
              for (final av in avisos)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(av.grave ? Icons.cancel : Icons.info_outline,
                          size: 14,
                          color: av.grave
                              ? const Color(0xFFC62828)
                              : const Color(0xFFB26A00)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(av.texto,
                            style: TextStyle(
                                fontSize: 11.5,
                                height: 1.35,
                                color: cessumMuted(context))),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// (2-oct-2026) «11:30-13:00», «11:30 a 13:00» y «11:30 - 13:00» son la MISMA
  /// franja. Las asignaciones capturadas a mano traen la hora como se tecleó, y
  /// comparar el texto crudo hacía que una franja ocupada pareciera libre.
  String _normHoraFranja(String h) {
    final m = RegExp(r'(\d{1,2})\s*[:.]\s*(\d{2})\s*(?:-|–|—|al|a)\s*(\d{1,2})\s*[:.]\s*(\d{2})')
        .firstMatch(h.trim());
    if (m == null) return h.trim();
    String d2(String x) => x.padLeft(2, '0');
    return '${d2(m.group(1)!)}:${m.group(2)} - ${d2(m.group(3)!)}:${m.group(4)}';
  }

  int? _semanasSel;

  // (28-sep) FASE 0: las reglas ya no se deciden aquí. _reglaDe (arriba, al
  // inicio del archivo) es la fuente única; cada getter solo la consulta con
  // el programa y el grupo/tipo actuales. Antes de este cambio, 5 funciones
  // reimplementaban su propio orden de condiciones — así apareció el bug de
  // hoy (sabatino ganaba sobre Maestría en Educación en _semanasDefault, sin
  // que las otras 4 funciones tuvieran el mismo defecto). Ver _reglaDe para
  // el porqué de cada caso.
  static const List<String> _defsHora = ['19:30-21:00', '10:00-12:00'];

  _ReglaAsignacion get _regla =>
      _reglaDe(_valProg(), '${_valGrupo()} ${_valTipo()}');

  bool get _esLicenciatura => _normaPrograma(_valProg()).contains('licenciatura');

  List<String> get _bloquesHorario => _regla.bloques;

  /// Programas con horario institucional fijo.
  bool get _tieneHorarioFijo => _regla.horarioFijo;

  String get _horaPredeterminada => _regla.horaPredeterminada;

  void _sincronizarHoraPredeterminada() {
    if (_esMixta) return;
    final def = _horaPredeterminada;
    if (def.isEmpty) return;
    final actual = _cHora.text.trim();
    if (actual.isEmpty ||
        (_defsHora.contains(actual) && actual != def)) {
      _cHora.text = def;
    }
  }

  int get _semanasDefault => _regla.semanas;

  int get _semanas => _semanasSel ?? _semanasDefault;
  /* (15-sep) En licenciatura las siete materias corren EN PARALELO todo el
     cuatrimestre: no hay receso entre ellas, porque no se encadenan. El
     receso de 1 o 2 semanas es de los programas por bloques. */
  int get _recesoSemanas => _semanas >= 12
      ? 0
      : (_semanas >= 10 ? 2 : (_semanas == 4 ? 0 : 1));

  String _isoFecha(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  void _aplicarInicioLunes(DateTime lunes) {
    _cInicio.text = _isoFecha(lunes);
    _cTermino.text =
        _isoFecha(lunes.add(Duration(days: _semanas * 7 - 1)));
    setState(() {});
    _cargarDisponibilidad();
    _cargarBloquesGrupo();
  }

  Future<void> _elegirLunesInicio() async {
    final hoy = DateTime.now();
    var d0 = DateTime(hoy.year, hoy.month, hoy.day);
    while (d0.weekday != DateTime.monday) {
      d0 = d0.add(const Duration(days: 1));
    }
    // (2-oct-2026) El selector arrancaba SIEMPRE en «el próximo lunes de hoy»,
    // sin importar el grupo: bastaba con tocar Aplicar para dejar el inicio
    // una semana corrido. Ahora parte del inicio ya escrito o, si no hay, del
    // sugerido del grupo, y solo cae en el próximo lunes si no hay ninguno.
    final sugInicio = _rangoSugerido();
    final base = _fechaIso(_cInicio.text.trim()) ??
        (sugInicio == null ? null : _fechaIso(sugInicio['inicio'] ?? ''));
    if (base != null) d0 = _lunesDe(base);
    final pick = await showDatePicker(
      context: context,
      initialDate: d0,
      firstDate: DateTime(hoy.year - 1),
      lastDate: DateTime(hoy.year + 2),
      selectableDayPredicate: (d) => d.weekday == DateTime.monday,
      helpText: 'Elige el LUNES de inicio',
      confirmText: 'Aplicar',
      cancelText: 'Cancelar',
    );
    if (pick != null) {
      _aplicarInicioLunes(DateTime(pick.year, pick.month, pick.day));
    }
  }

  // Recalcula el término cuando cambian las semanas y ya hay un inicio lunes.
  void _recalcularTermino() {
    final ini = _fechaIso(_cInicio.text.trim());
    if (ini != null && ini.weekday == DateTime.monday) {
      _cTermino.text =
          _isoFecha(ini.add(Duration(days: _semanas * 7 - 1)));
    }
  }

  // Rango sugerido: último término del grupo + receso → siguiente lunes.
  // (30-sep-2026) EN SABATINO DE POSGRADO esto estaba mal: siempre
  // proponía el bloque siguiente al último término de CUALQUIER materia,
  // sin revisar si el bloque VIGENTE (dos franjas fijas) ya tenía sus dos
  // materias o le faltaba una. Caso real: Educación Inclusiva 26-1 grupo
  // 2, bloque 28-sep al 06-dic con solo una materia (11:30-13:00) — el
  // sistema mandaba la nueva materia al bloque de después del receso, en
  // vez de llenar el hueco de 10:00-11:30 en el mismo bloque.
  // Ahora: en sabatino de posgrado, se agrupan las asignaciones del grupo
  // por su rango EXACTO (inicio, término) — cada rango compartido es un
  // bloque de 10 semanas. Si el bloque de término más reciente tiene
  // MENOS de 2 asignaciones (una franja libre), se propone ESE MISMO
  // rango; solo se avanza al bloque siguiente cuando ya tiene las dos.
  Map<String, String>? _rangoSugerido() {
    final prog = _valProg().trim();
    final gen = _valGen().trim();
    final gr = _valGrupo().trim();
    if (prog.isEmpty || gr.isEmpty) return null;

    final esSabatinoPosgrado = _bloquesHorario.length == 2 && !_esLicenciatura;

    if (esSabatinoPosgrado) {
      // (2-oct-2026) SOLO EL BLOQUE MÁS RECIENTE DECIDE. Antes se recorrían
      // TODOS los bloques del grupo y se proponía el primero que tuviera
      // menos de 2 materias, aunque hubiera terminado hacía meses. Caso real,
      // Maestría en Pedagogía 26-1 grupo 2: el bloque abril–junio solo tuvo
      // una materia (Psicología del Aprendizaje), y la pantalla lo proponía
      // como «hueco» por llenar —con fechas de abril— cuando el bloque más
      // reciente (julio–septiembre) ya estaba completo y lo que tocaba era el
      // siguiente. De ahí salían los tres síntomas: franja «ocupada» por una
      // materia que terminó el 21 de junio, bloque anterior de enero–marzo y
      // fechas de abril en el formulario.
      // Reglas ahora:
      //  · Un bloque es el conjunto de materias con el MISMO TÉRMINO, comparado
      //    como fecha (no como texto).
      //  · Solo se propone llenar un hueco si el bloque más reciente todavía
      //    no termina (vigente o por empezar) y le falta una franja.
      //  · Si está completo, o ya terminó, se propone el bloque siguiente.
      final hoy = DateTime.now();
      final hoyDia = DateTime(hoy.year, hoy.month, hoy.day);
      final porTermino = <String, List<Map<String, dynamic>>>{};
      final terminoDe = <String, DateTime>{};
      final inicioDe = <String, DateTime>{};
      for (final a in widget.asignaciones) {
        if (_esLaEditada(a)) continue; // la que se edita no es «anterior» de sí misma
        if (_normaPrograma('${a['programa'] ?? ''}') != _normaPrograma(prog)) continue;
        if ((a['generacion'] ?? '').toString().trim() != gen) continue;
        if ((a['grupo'] ?? '').toString().trim() != gr) continue;
        final ini = _fechaIso((a['inicio'] ?? '').toString());
        final fin = _fechaIso((a['termino'] ?? '').toString());
        if (ini == null || fin == null) continue; // sin fechas legibles no forma bloque
        final kf = _isoFecha(fin);
        porTermino.putIfAbsent(kf, () => []).add(a);
        terminoDe[kf] = fin;
        final previo = inicioDe[kf];
        if (previo == null || ini.isBefore(previo)) inicioDe[kf] = ini;
      }
      if (porTermino.isNotEmpty) {
        final claves = porTermino.keys.toList()
          ..sort((x, y) => terminoDe[y]!.compareTo(terminoDe[x]!)); // término más reciente primero
        final kUlt = claves.first;
        final finUlt = terminoDe[kUlt]!;
        if (porTermino[kUlt]!.length < 2 && !finUlt.isBefore(hoyDia)) {
          // Hueco en el bloque vigente: falta una de las dos franjas. Se
          // propone este mismo rango para llenarlo.
          return {'inicio': _isoFecha(inicioDe[kUlt]!), 'fin': _isoFecha(finUlt)};
        }
        // Bloque completo (o ya terminado): se avanza desde su término.
        var cand = finUlt.add(Duration(days: 1 + _recesoSemanas * 7));
        while (cand.weekday != DateTime.monday) {
          cand = cand.add(const Duration(days: 1));
        }
        final finNuevo = cand.add(Duration(days: _semanas * 7 - 1));
        return {'inicio': _isoFecha(cand), 'fin': _isoFecha(finNuevo)};
      }
      // Sin histórico de este grupo: cae al cálculo genérico de abajo.
    }

    DateTime? ultimo;
    for (final a in widget.asignaciones) {
      if (_esLaEditada(a)) continue; // la que se edita no es «anterior» de sí misma
      if (_normaPrograma('${a['programa'] ?? ''}') != _normaPrograma(prog)) continue;
      if ((a['generacion'] ?? '').toString().trim() != gen) continue;
      if ((a['grupo'] ?? '').toString().trim() != gr) continue;
      final f = _fechaIso((a['termino'] ?? '').toString());
      if (f != null && (ultimo == null || f.isAfter(ultimo))) ultimo = f;
    }
    if (ultimo == null) return null;
    var cand = ultimo.add(Duration(days: 1 + _recesoSemanas * 7));
    while (cand.weekday != DateTime.monday) {
      cand = cand.add(const Duration(days: 1));
    }
    final fin = cand.add(Duration(days: _semanas * 7 - 1));
    return {'inicio': _isoFecha(cand), 'fin': _isoFecha(fin)};
  }

  Widget _panelFechasAuto() {
    _sincronizarHoraPredeterminada();
    final sug = _rangoSugerido();
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cessumRed.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cessumRed.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Fechas automáticas',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  color: cessumRed)),
          Text(
            // El texto ya no anuncia un horario que no existe. Solo la
            // Maestría en Educación tiene sesión semanal institucional; en
            // los demás programas la hora la acuerda el docente con su grupo.
            _horaPredeterminada.isEmpty
                ? 'Inicio en lunes · término en domingo de la última semana. '
                  'La hora la defines tú con tu grupo: escríbela en el campo Hora.'
                : 'Inicio en lunes · término en domingo de la última semana. '
                  'Horario institucional de este programa: $_horaPredeterminada '
                  '(edítalo en el campo Hora si tu caso es distinto).',
            style: TextStyle(fontSize: 11, color: cessumMuted(context)),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('Semanas:', style: TextStyle(fontSize: 12)),
              // (15-sep) Se agregan 12, 13, 14 y 16 para los cuatrimestres de
              // licenciatura: el de sep-dic 2026 son 14 semanas, pero cambia
              // según cuántos sábados caigan en el periodo.
              for (final n in const [4, 5, 10, 12, 13, 14, 16])
                ChoiceChip(
                  label: Text(
                      n == 4
                          ? '4 · M. Educación'
                          : n == 5
                              ? '5 · Entre semana'
                              : n == 10
                                  ? '10 · Sabatino'
                                  : '$n · Licenciatura',
                      style: const TextStyle(fontSize: 11)),
                  selected: _semanas == n,
                  selectedColor: cessumRed.withValues(alpha: 0.15),
                  onSelected: (_) => setState(() {
                    _semanasSel = n;
                    _recalcularTermino();
                  }),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: cessumRed,
                  side: const BorderSide(color: cessumRed),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                onPressed: _elegirLunesInicio,
                icon: const Icon(Icons.calendar_month, size: 18),
                label: Text('Elegir lunes de inicio · $_semanas semanas',
                    style: const TextStyle(fontSize: 12)),
              ),
              if (sug != null)
                ActionChip(
                  avatar: const Icon(Icons.auto_awesome,
                      size: 16, color: Color(0xFF1E6FD9)),
                  label: Text('Sugerido: ${sug['inicio']} → ${sug['fin']}',
                      style: const TextStyle(fontSize: 11)),
                  onPressed: () {
                    _cInicio.text = sug['inicio']!;
                    _cTermino.text = sug['fin']!;
                    setState(() {});
                    _cargarDisponibilidad();
                    _cargarBloquesGrupo();
                  },
                ),
            ],
          ),
          if (sug != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _recesoSemanas == 0
                    ? 'Programa continuo: reanuda el lunes inmediato al '
                        'último término del grupo.'
                    : 'El sugerido respeta $_recesoSemanas semana(s) de '
                        'receso tras el último término del grupo.',
                style:
                    const TextStyle(fontSize: 10.5, color: Colors.black54),
              ),
            ),
        ],
      ),
    );
  }

  /// Las materias del plan del programa elegido, tal como las sirvió el
  /// backend al cargar el formulario.
  List<String> _materiasDelPlanActual() {
    final out = <String>[];
    for (final m in _materiasSugeridas) {
      final n = (m['denominacion'] ?? m['materia'] ?? '').toString().trim();
      if (n.isNotEmpty) out.add(n);
    }
    return out;
  }

  /// Compara lo escrito contra las materias del plan del programa elegido.
  ///
  /// Solo avisa cuando hay plan cargado: si no lo hay, no se puede afirmar
  /// que la materia esté mal, y una alerta falsa enseña a ignorar las alertas.
  Widget _avisoMateriaFueraDelPlan() {
    final escrita = _cMateria.text.trim();
    if (escrita.isEmpty) return const SizedBox.shrink();

    final delPlan = _materiasDelPlanActual();
    if (delPlan.isEmpty) return const SizedBox.shrink();

    String norm(String x) => x
        .toLowerCase()
        .replaceAll(RegExp('[áàä]'), 'a')
        .replaceAll(RegExp('[éèë]'), 'e')
        .replaceAll(RegExp('[íìï]'), 'i')
        .replaceAll(RegExp('[óòö]'), 'o')
        .replaceAll(RegExp('[úùü]'), 'u')
        .replaceAll(RegExp(r'[^a-z0-9]'), '');

    final n = norm(escrita);
    if (delPlan.any((m) => norm(m) == n)) return const SizedBox.shrink();

    // Buscar el parecido más cercano, para poder sugerirlo.
    String? cercana;
    for (final m in delPlan) {
      final a = norm(m);
      if (a.contains(n) || n.contains(a)) {
        cercana = m;
        break;
      }
    }

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: cessumGold.withValues(alpha: 0.4)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.info_outline, size: 16, color: cessumGold),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Esta materia no está en el plan del programa',
                  style: TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                  cercana != null
                      ? '¿Quisiste decir «$cercana»? Un nombre distinto hace '
                          'que el sistema las vea como dos materias, y sus '
                          'calificaciones dejan de cruzar.'
                      : 'Si es correcta, adelante. Si no, cárgala del plan: '
                          'escribirla distinto hace que sus calificaciones no '
                          'crucen después.',
                  style: const TextStyle(fontSize: 11.5, height: 1.45)),
              if (cercana != null) ...[
                const SizedBox(height: 5),
                TextButton(
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                      foregroundColor: cessumGold),
                  onPressed: () =>
                      setState(() => _cMateria.text = cercana!),
                  child: Text('Usar «$cercana»',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          ),
        ),
      ]),
    );
  }

  Widget _texto(String label, TextEditingController c,
      {ValueChanged<String>? onCambio}) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: TextField(
          controller: c, decoration: _dec(label), onChanged: onCambio),
    );
  }

  // Cuando el usuario termina de escribir una fecha completa (AAAA-MM-DD),
  // recalcula la disponibilidad de maestros con la vigencia incluida.
  void _refrescarDispSiFechaCompleta(String v) {
    final t = v.trim();
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(t)) {
      _cargarDisponibilidad();
      _cargarBloquesGrupo();
    }
  }

  // Carga el padrón de profesores para el desplegable de maestro.
  Future<void> _cargarProfes() async {
    try {
      final uri = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'profesores_padron'});
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] == true && data['profesores'] is List) {
        final lista = (data['profesores'] as List)
            .map((e) => {
                  'nombre': (e['nombre'] ?? '').toString(),
                  'correo': (e['correo'] ?? '').toString(),
                })
            .where((m) => (m['nombre'] ?? '').isNotEmpty)
            .toList();
        if (!mounted) return;
        setState(() {
          _profes = lista;
          final actual = _cDocente.text.trim().toLowerCase();
          final correoActual = _cCorreo.text.trim().toLowerCase();
          Map<String, String>? enLista;
          for (final p in _profes) {
            if ((p['nombre'] ?? '').toLowerCase() == actual ||
                (correoActual.isNotEmpty &&
                    (p['correo'] ?? '').toLowerCase() == correoActual)) {
              enLista = p;
              break;
            }
          }
          if (actual.isNotEmpty && enLista == null) {
            _maestroManual = true; // un docente que no está en el padrón
          } else if (enLista != null) {
            _maestroSelCorreo = (enLista['correo'] ?? '').isNotEmpty
                ? enLista['correo']
                : enLista['nombre'];
          }
        });
      }
    } catch (e, s) {
      // (28-sep, Fase 3) Sigue cayendo a captura manual del docente —no vale
      // la pena un diálogo por esto— pero ahora queda registrado.
      ErrorReporter.reportar(e, s, pantallaForzada: 'agenda:profesores_padron');
      if (mounted) setState(() => _maestroManual = true);
    }
  }

  // Selector de maestro: desplegable del padrón, con opción de escribir a mano.
  // (29-sep) Sugerencia con IA: junta en UNA llamada lo que hoy hay que
  // revisar por separado (quién ya la impartió, perfil acorde, horario de
  // cada candidato, lo que ya tiene el grupo) y devuelve una recomendación
  // concreta lista para usar con un clic — el admin sigue decidiendo, esto
  // solo ahorra la vuelta por cuatro pantallas distintas.
  Future<void> _sugerirConIa() async {
    final materia = _cMateria.text.trim();
    final prog = _valProg(), grp = _valGrupo();
    if (materia.isEmpty || prog.isEmpty || grp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Elige programa, grupo y materia primero.'),
      ));
      return;
    }
    setState(() {
      _cargandoIa = true;
      _errorIa = null;
      _sugerenciaIa = null;
      _alternativasIa = [];
    });
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'asignacion_sugerir_ia',
        'programa': prog,
        'generacion': _valGen(),
        'grupo': grp,
        'materia': materia,
        'actor': await SessionStore.realEmail() ?? '',
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        setState(() {
          _sugerenciaIa =
              Map<String, dynamic>.from(data['recomendacion'] as Map);
          _alternativasIa = ((data['alternativas'] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _cargandoIa = false;
        });
      } else {
        setState(() {
          _errorIa = (data['error'] ?? 'No se pudo obtener una sugerencia.').toString();
          _cargandoIa = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorIa = 'No se pudo conectar: $e';
        _cargandoIa = false;
      });
    }
  }

  // Aplica la recomendación (o una alternativa) a los campos del formulario.
  void _usarSugerenciaIa(Map<String, dynamic> rec) {
    final correo = (rec['correo'] ?? '').toString().trim().toLowerCase();
    final nombre = (rec['docente'] ?? '').toString().trim();
    Map<String, String>? enLista;
    for (final p in _profes) {
      if (correo.isNotEmpty && (p['correo'] ?? '').toLowerCase() == correo) {
        enLista = p;
        break;
      }
    }
    setState(() {
      if (enLista != null) {
        _maestroManual = false;
        _maestroSelCorreo = (enLista['correo'] ?? '').isNotEmpty
            ? enLista['correo']
            : enLista['nombre'];
        _cDocente.text = enLista['nombre'] ?? '';
        _cCorreo.text = enLista['correo'] ?? '';
      } else {
        _maestroManual = true;
        _cDocente.text = nombre;
        _cCorreo.text = correo;
      }
      final dia = (rec['dia'] ?? '').toString().trim();
      _dia = (dia.isEmpty || !_dias.contains(dia)) ? null : dia;
      _cHora.text = (rec['hora'] ?? '').toString().trim();
    });
    _cargarBloquesGrupo();
    _cargarHorarioMaestro(_cCorreo.text.trim());
    _cargarDisponibilidad();
  }

  Widget _tarjetaSugerenciaIa() {
    if (_cargandoIa) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: cessumRed)),
          SizedBox(width: 10),
          Text('Pensando la mejor opción…', style: TextStyle(fontSize: 12.5)),
        ]),
      );
    }
    if (_errorIa != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text('⚠ $_errorIa',
            style: TextStyle(fontSize: 11.5, color: Colors.orange.shade800)),
      );
    }
    final rec = _sugerenciaIa;
    if (rec == null) return const SizedBox.shrink();
    final diaHora = [rec['dia'], rec['hora']]
        .where((x) => (x ?? '').toString().trim().isNotEmpty)
        .join(' · ');
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cessumRed.withValues(alpha: 0.05),
        border: Border.all(color: cessumRed.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.auto_awesome, size: 17, color: cessumRed),
            const SizedBox(width: 6),
            const Expanded(
              child: Text('Sugerencia',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: cessumRed)),
            ),
          ]),
          const SizedBox(height: 6),
          Text('${rec['docente']}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          if (diaHora.isNotEmpty)
            Text(diaHora, style: const TextStyle(fontSize: 12.5)),
          if ((rec['razon'] ?? '').toString().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${rec['razon']}',
                  style: TextStyle(fontSize: 11.5, color: cessumMuted(context), height: 1.35)),
            ),
          const SizedBox(height: 8),
          Row(children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () => _usarSugerenciaIa(rec),
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Usar esta'),
            ),
          ]),
          if (_alternativasIa.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Alternativas', style: TextStyle(fontSize: 11, color: cessumMuted(context))),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _alternativasIa.map((a) {
                return ActionChip(
                  label: Text('${a['docente']}', style: const TextStyle(fontSize: 11.5)),
                  onPressed: () => _usarSugerenciaIa(a),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // (30-sep) Se dispara igual que _cargarSugeridos, con el mismo evento
  // (cambio de materia) — así el admin ve la advertencia EN EL MOMENTO en
  // que elige la materia, tanto si la escribió a mano como si usó "Armar
  // propuesta" o los chips de sugeridos.
  /// (2-oct) Agrupa [{materia, periodo}] por semestre/cuatrimestre, en el orden en que llegan.
  Map<String, List<String>> _faltantesPorPeriodo(List items) {
    final out = <String, List<String>>{};
    for (final e in items) {
      final m = e is Map ? e : const {};
      final per = '${m['periodo'] ?? ''}'.trim();
      final mat = '${m['materia'] ?? ''}'.trim();
      if (mat.isEmpty) continue;
      out.putIfAbsent(per.isEmpty ? 'Otras materias' : per, () => <String>[]).add(mat);
    }
    return out;
  }

  /// La lista de materias faltantes, UNA sola vez y agrupada por semestre.
  Widget _listaFaltantesPorPeriodo(List items, {double fontSize = 12.5}) {
    final grupos = _faltantesPorPeriodo(items);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in grupos.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Text(e.key,
                style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800)),
          ),
          for (final m in e.value)
            Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 2),
              child: Text('• $m', style: TextStyle(fontSize: fontSize)),
            ),
        ],
      ],
    );
  }

  Future<void> _verificarOrdenCurricular() async {
    final mat = _cMateria.text.trim();
    final prog = _valProg();
    // (2-oct) La clave incluye programa, generación y grupo: antes solo era la
    // materia, y al cambiar de grupo el aviso se quedaba con el resultado del anterior.
    final claveOrden = '$prog|${_valGen()}|${_valGrupo()}|$mat';
    if (mat.isEmpty || prog.isEmpty || claveOrden == _ordenMateriaVerificada) return;
    _ordenMateriaVerificada = claveOrden;
    if (mounted && _ordenFaltantes != null) setState(() => _ordenFaltantes = null);
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'asignacion_orden_verificar',
        'programa': prog,
        'generacion': _valGen(),
        'grupo': _valGrupo(),
        'materia': mat,
        'actor': await SessionStore.realEmail() ?? '',
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 25));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        setState(() {
          _ordenFaltantes = ((data['faltan'] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        });
      }
    } catch (_) {
      // Silencioso: esto es una ayuda visual, no un candado — el candado
      // real sigue corriendo en el servidor al guardar, pase lo que pase aquí.
    }
  }

  Widget _bannerOrdenCurricular() {
    final f = _ordenFaltantes;
    if (f == null || f.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cessumRed.withValues(alpha: 0.08),
        border: Border.all(color: cessumRed.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.warning_amber_rounded, size: 18, color: cessumRed),
            const SizedBox(width: 6),
            const Expanded(
              child: Text('Este grupo se saltaría materias',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: cessumRed)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            'Todavía no tiene registrada${f.length == 1 ? '' : 'n'}:',
            style: const TextStyle(fontSize: 12.5),
          ),
          _listaFaltantesPorPeriodo(f),
          const SizedBox(height: 6),
          const Text(
            'Al guardar, el sistema lo va a bloquear a menos que confirmes '
            'que en verdad se debe saltar el orden.',
            style: TextStyle(fontSize: 11.5, color: Colors.black54, height: 1.3),
          ),
        ],
      ),
    );
  }

  Future<void> _cargarSugeridos() async {
    final mat = _cMateria.text.trim();
    if (mat.isEmpty || mat == _sugMateria || _sugCargando) return;
    _sugCargando = true;
    _sugMateria = mat;
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'docentes_sugeridos',
        'materia': mat,
        'programa': _valProg(),
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() => _sugeridos = data['ok'] == true ? data : null);
    } catch (e, s) {
      // (28-sep, Fase 3) Sigue mostrando la lista sin sugeridos —no vale la
      // pena un diálogo por esto— pero ahora queda registrado.
      ErrorReporter.reportar(e, s, pantallaForzada: 'agenda:docentes_sugeridos');
      if (mounted) setState(() => _sugeridos = null);
    } finally {
      _sugCargando = false;
    }
  }

  void _elegirSugerido(Map<String, dynamic> d) {
    final correo = (d['correo'] ?? '').toString().trim().toLowerCase();
    final nombre = (d['nombre'] ?? '').toString().trim();
    Map<String, String>? enLista;
    for (final p in _profes) {
      if (correo.isNotEmpty && (p['correo'] ?? '').toLowerCase() == correo) {
        enLista = p;
        break;
      }
    }
    setState(() {
      if (enLista != null) {
        _maestroManual = false;
        _maestroSelCorreo = (enLista['correo'] ?? '').isNotEmpty
            ? enLista['correo']
            : enLista['nombre'];
        _cDocente.text = enLista['nombre'] ?? '';
        _cCorreo.text = enLista['correo'] ?? '';
      } else {
        // No está en el padrón de la lista (o no tiene correo): a mano.
        _maestroManual = true;
        _cDocente.text = nombre.replaceFirst(RegExp(r'^(Dr|Dra|Mtro|Mtra|Lic|Ing)\.?\s+'), '');
        _cCorreo.text = correo;
      }
    });
    // (29-sep) Elegir por chip ("Ya la impartieron" / "Perfil acorde") es
    // otra forma de elegir al maestro, igual que el dropdown — así que
    // también debe cargar su horario actual, no solo llenar el nombre.
    _cargarBloquesGrupo();
    _cargarHorarioMaestro(_cCorreo.text.trim());
  }

  Widget _sugeridosUI() {
    // Se consulta cuando cambia la materia; el Guardián responde rápido.
    if (_cMateria.text.trim().isNotEmpty && _cMateria.text.trim() != _sugMateria) {
      Future.microtask(_cargarSugeridos);
    }
    // (30-sep) Misma señal de cambio, para el aviso de orden curricular.
    final claveOrden = '${_valProg()}|${_valGen()}|${_valGrupo()}|${_cMateria.text.trim()}';
    if (_cMateria.text.trim().isNotEmpty && claveOrden != _ordenMateriaVerificada) {
      Future.microtask(_verificarOrdenCurricular);
    }
    final bannerOrden = _bannerOrdenCurricular();
    // (29-sep) El botón de IA va primero y NO depende de si los chips de
    // abajo tienen datos — con materia+programa+grupo alcanza para pedirla.
    final puedeSugerir = _cMateria.text.trim().isNotEmpty &&
        _valProg().isNotEmpty && _valGrupo().isNotEmpty;
    final botonIa = puedeSugerir
        ? Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                bannerOrden,
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: cessumRed),
                    onPressed: _cargandoIa ? null : _sugerirConIa,
                    icon: const Icon(Icons.auto_awesome, size: 16),
                    label: Text(_sugerenciaIa == null
                        ? 'Sugerir con IA'
                        : 'Sugerir de nuevo'),
                  ),
                ),
                _tarjetaSugerenciaIa(),
              ],
            ),
          )
        : bannerOrden;
    final s = _sugeridos;
    if (s == null) return botonIa;
    final ya = ((s['yaImpartieron'] as List?) ?? [])
        .map((x) => Map<String, dynamic>.from(x as Map))
        .toList();
    final perfil = ((s['perfilAcorde'] as List?) ?? [])
        .map((x) => Map<String, dynamic>.from(x as Map))
        .toList();
    if (ya.isEmpty && perfil.isEmpty) return botonIa;
    final hint = Theme.of(context).hintColor;
    Widget chip(Map<String, dynamic> d, String detalle, IconData icono, Color color) {
      final correo = (d['correo'] ?? '').toString().toLowerCase();
      final elegido = correo.isNotEmpty && _maestroSelCorreo == correo;
      return ActionChip(
        avatar: Icon(icono, size: 16, color: color),
        label: Text('${d['nombre']} · $detalle',
            style: TextStyle(fontSize: 12.5, fontWeight: elegido ? FontWeight.w700 : FontWeight.w500)),
        backgroundColor: elegido ? color.withValues(alpha: 0.15) : null,
        side: BorderSide(color: color.withValues(alpha: elegido ? 0.9 : 0.4)),
        onPressed: () => _elegirSugerido(d),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          botonIa,
          Text('Sugeridos para «${s['materia']}»',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          if (ya.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Ya la impartieron', style: TextStyle(fontSize: 11, color: hint)),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: ya
                  .map((d) => chip(
                      d,
                      '${d['veces']} ${(d['veces'] as num?) == 1 ? 'vez' : 'veces'}'
                      '${(d['ultima'] ?? '').toString().isNotEmpty ? ' · última ${d['ultima']}' : ''}',
                      Icons.star,
                      cessumRed))
                  .toList(),
            ),
          ],
          if (perfil.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Perfil acorde', style: TextStyle(fontSize: 11, color: hint)),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: perfil
                  .map((d) => chip(
                      d,
                      'perfil: ${((d['coincide'] as List?) ?? []).join(', ')}',
                      Icons.person_search,
                      cessumGold))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _selectorMaestro() {
    if (_maestroManual || _profes.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sugeridosUI(),
          _texto('Maestro (nombre)', _cDocente),
          const SizedBox(height: 10),
          _texto('Correo del maestro (@cessum.mx)', _cCorreo),
          _tarjetaHorarioMaestro(),
          if (_profes.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _maestroManual = false),
                icon: const Icon(Icons.list, size: 18, color: cessumRed),
                label: const Text('Elegir de la lista',
                    style: TextStyle(color: cessumRed)),
              ),
            ),
        ],
      );
    }
    String llave(Map<String, String> p) =>
        (p['correo'] ?? '').isNotEmpty ? p['correo']! : (p['nombre'] ?? '');
    final q = _filtroProfes.text.trim().toLowerCase();
    final visibles = q.isEmpty
        ? _profes
        : _profes.where((p) {
            final heno =
                '${p['nombre'] ?? ''} ${p['correo'] ?? ''}'.toLowerCase();
            return q.split(RegExp(r'\s+')).every((w) => heno.contains(w));
          }).toList();
    // El ya elegido nunca se filtra, para que el valor no quede huérfano.
    if (_maestroSelCorreo != null &&
        !visibles.any((p) => llave(p) == _maestroSelCorreo)) {
      final sel = _profes.where((p) => llave(p) == _maestroSelCorreo);
      if (sel.isNotEmpty) visibles.insert(0, sel.first);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sugeridosUI(),
        if (_profes.length > 8) ...[
          TextField(
            controller: _filtroProfes,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 19),
              suffixIcon: _filtroProfes.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _filtroProfes.clear()),
                    ),
              hintText: 'Buscar maestro por nombre o correo',
              hintStyle: const TextStyle(fontSize: 13.5),
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 8),
        ],
        // (23-sep) Si la revisión de disponibilidad no respondió, que se sepa.
        if (_dispFallo)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '⚠ No se pudo revisar quién está ocupado ese día y hora. Nadie aparece como ocupado, '
              'pero puede haber choques: se validarán al guardar.',
              style: TextStyle(fontSize: 11.5, color: Colors.orange.shade800, fontWeight: FontWeight.w600),
            ),
          ),
        DropdownButtonFormField<String>(
          value: _maestroSelCorreo,
          isExpanded: true,
          decoration: _dec('Maestro'),
          hint: const Text('Elige al maestro'),
          // (16-sep) LOS OCUPADOS YA NO SE ESCONDEN, SE MARCAN.
          // Antes desaparecían del desplegable, así que un docente con clases
          // ese día simplemente no estaba —y quien capturaba no sabía si le
          // faltaba en el padrón o si tenía choque. Ahora aparece con el
          // motivo a la vista y se puede elegir: el choque real se valida al
          // guardar, que es donde corresponde.
          items: visibles
              .map((p) {
                final ocupado =
                    _ocupados.contains((p['correo'] ?? '').toLowerCase());
                final motivo =
                    _conflicto[(p['correo'] ?? '').toLowerCase()] ?? '';
                final base = (p['correo'] ?? '').isNotEmpty
                    ? '${p['nombre']}  (${p['correo']})'
                    : (p['nombre'] ?? '');
                return DropdownMenuItem<String>(
                  value: llave(p),
                  child: Text(
                    ocupado
                        ? '$base  · ocupado${motivo.isNotEmpty ? ': $motivo' : ''}'
                        : base,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ocupado
                        ? TextStyle(color: cessumMuted(context))
                        : null,
                  ),
                );
              })
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            final p = _profes.firstWhere((x) => llave(x) == v,
                orElse: () => {'nombre': '', 'correo': ''});
            setState(() {
              _maestroSelCorreo = v;
              _cDocente.text = p['nombre'] ?? '';
              _cCorreo.text = p['correo'] ?? '';
            });
            _cargarBloquesGrupo(); // el docente elegido también puede tener choque
            _cargarHorarioMaestro(p['correo'] ?? ''); // qué ya está dando, para decidir la hora
          },
        ),
        _tarjetaHorarioMaestro(),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _maestroManual = true),
            icon: const Icon(Icons.edit, size: 18, color: cessumRed),
            label: const Text('Escribir a mano (no está en la lista)',
                style: TextStyle(color: cessumRed)),
          ),
        ),
      ],
    );
  }

  InputDecoration _dec(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: cessumMuted(context).withValues(alpha: 0.18))),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: cessumMuted(context).withValues(alpha: 0.18))),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: cessumRed)),
    );
  }
}

/// (23-sep) Hoja con los alumnos del curso o del programa: buscador, total,
/// secciones por generación y grupo, y copia de la lista para Excel.
class _HojaAlumnosCurso extends StatefulWidget {
  final String titulo;
  final String nota;
  final Future<List<Map<String, dynamic>>> Function() cargar;
  const _HojaAlumnosCurso({required this.titulo, required this.nota, required this.cargar});

  @override
  State<_HojaAlumnosCurso> createState() => _HojaAlumnosCursoState();
}

class _HojaAlumnosCursoState extends State<_HojaAlumnosCurso> {
  List<Map<String, dynamic>>? _lista;
  String _error = '';
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.cargar().then((l) {
      if (mounted) setState(() => _lista = l);
    }).catchError((Object e) {
      if (mounted) setState(() => _error = 'No se pudo cargar la lista. Revise su conexión e intente de nuevo.');
    });
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _normaPrograma(_q.text);
    final todos = _lista ?? const <Map<String, dynamic>>[];
    final vis = q.isEmpty
        ? todos
        : todos.where((m) => _normaPrograma('${m['nombre'] ?? ''} ${m['matricula'] ?? ''} ${m['correo'] ?? ''}').contains(q)).toList();
    final filas = <Widget>[];
    String seccion = '';
    for (final m in vis) {
      final sec = '${m['seccion'] ?? ''}';
      if (sec.isNotEmpty && sec != seccion) {
        seccion = sec;
        final n = vis.where((x) => '${x['seccion'] ?? ''}' == sec).length;
        filas.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Text('$sec · $n', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: cessumRed)),
        ));
      }
      // El Guardián marca a quien recursa con este grupo (alumnosDeGrupo).
      final recursa = m['recursamiento'] == true;
      final matRec = '${m['materiaRecursa'] ?? ''}'.trim();
      filas.add(ListTile(
        dense: true,
        leading: CircleAvatar(
          radius: 15,
          backgroundColor: cessumRed.withValues(alpha: 0.12),
          child: Text(('${m['nombre'] ?? '?'}'.trim().isEmpty ? '?' : '${m['nombre']}'.trim()[0]).toUpperCase(),
              style: const TextStyle(fontSize: 12, color: cessumRed, fontWeight: FontWeight.w800)),
        ),
        title: Text('${m['nombre'] ?? ''}', style: const TextStyle(fontSize: 13.5)),
        subtitle: Text('${m['matricula'] ?? ''}${'${m['correo'] ?? ''}'.isNotEmpty ? ' · ${m['correo']}' : ''}',
            style: const TextStyle(fontSize: 11.5)),
        trailing: recursa
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: cessumGold.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                child: Text(matRec.isNotEmpty ? 'Recursa $matRec' : 'Recursa',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              )
            : null,
      ));
    }
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.titulo, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(widget.nota, style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
                ]),
              ),
              if (vis.isNotEmpty)
                IconButton(
                  tooltip: 'Copiar la lista (nombre, matrícula y correo) para Excel',
                  icon: const Icon(Icons.copy_all_outlined, color: cessumRed),
                  onPressed: () {
                    final b = StringBuffer()..writeln('Nombre\tMatrícula\tCorreo\tGrupo');
                    for (final m in vis) {
                      b.writeln('${m['nombre'] ?? ''}\t${m['matricula'] ?? ''}\t${m['correo'] ?? ''}\t${m['seccion'] ?? ''}');
                    }
                    Helpers.copiarAlPortapapeles(context, b.toString(), 'Lista de ${vis.length} alumno(s)');
                  },
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: TextField(
              controller: _q,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                hintText: 'Buscar por nombre, matrícula o correo',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (_lista != null && _error.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                q.isEmpty ? '${todos.length} alumno(s)' : '${vis.length} de ${todos.length} alumno(s)',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          Expanded(
            child: _error.isNotEmpty
                ? Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(_error, textAlign: TextAlign.center)))
                : _lista == null
                    ? const Center(child: CircularProgressIndicator(color: cessumRed))
                    : vis.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                todos.isEmpty ? 'No hay alumnos registrados en este curso.' : 'Nadie coincide con la búsqueda.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: cessumMuted(context)),
                              ),
                            ),
                          )
                        : ListView(children: filas),
          ),
        ]),
      ),
    );
  }
}
