// ===========================================================================
//  GENERADOR DE DIAPOSITIVAS CON IA · Material didáctico
//  ---------------------------------------------------------------------------
//  El docente sube su material —PDF, Word, texto, imágenes—, elige cómo
//  quiere la presentación, y recibe un PowerPoint con la identidad de CESSUM,
//  los datos de su materia ya puestos, y preguntas que promueven interacciones
//  complejas al margen.
//
//  Dos rutas, a elección del docente:
//    · Colaborativa: la IA le hace 5-7 preguntas sobre acentos, ejemplos y
//      énfasis antes de proponer nada.
//    · Autónoma: la IA propone bajo su criterio, y de ahí se corrige.
//
//  En ambas, PRIMERO el índice (esqueleto), que el docente edita y aprueba, y
//  SOLO ENTONCES se generan las diapositivas. Hasta tres versiones por
//  proyecto, con retroalimentación entre una y otra.
//
//  La IA corre en el Guardián. La clave NUNCA está en esta app.
// ===========================================================================
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';
import 'aula_radiografia_screen.dart';
import 'biblioteca_screen.dart';   // (5-oct-2026) biblioteca de bloques
import 'diapo_revision_screen.dart';   // (8-oct-2026) chat de revisión lámina por lámina

// (3-oct-2026) Un error del servidor ya con su mensaje claro y su REFERENCIA (ER-…), que apunta al detalle técnico que guarda Vicerrectoría.
// «sistemico» = es un problema que se repetirá igual en las demás sesiones, así que no se insiste con ellas.
class _ErrorConRef implements Exception {
  final String mensaje;
  final String ref;
  final bool sistemico;
  const _ErrorConRef(this.mensaje, this.ref, this.sistemico);
  @override
  String toString() => mensaje;
}

class GeneradorDiapositivasScreen extends StatefulWidget {
  final Map<String, dynamic>? grupoInicial;
  /// (7-sep) Cuando la presentación nace de una planeación, llega con el
  /// material de esa sesión ya armado —tema, criterio de logro, los tres
  /// momentos y los abridores ya escritos— y el docente no tiene que volver
  /// a explicar nada. El identificador viaja para que el motor sepa que los
  /// abridores están aprobados y no debe reinventarlos.
  final String? materialInicial;
  final String? tituloInicial;
  final String? dePlaneacion;
  final int sesionDePlaneacion;
  const GeneradorDiapositivasScreen({
    super.key,
    this.grupoInicial,
    this.materialInicial,
    this.tituloInicial,
    this.dePlaneacion,
    this.sesionDePlaneacion = 0,
  });
  @override
  State<GeneradorDiapositivasScreen> createState() =>
      _GeneradorDiapositivasScreenState();
}

class _GeneradorDiapositivasScreenState
    extends State<GeneradorDiapositivasScreen> {
  // Estado del asistente
  int _paso = 0; // 0 materia · 1 material · 2 controles · 3 modo · 4 preguntas · 5 esqueleto · 6 versión
  String _correo = '';
  List<Map<String, dynamic>> _grupos = [];
  Map<String, dynamic>? _grupo;
  bool _cargando = true;
  bool _ocupado = false;

  // (10-sep) AVANCE POR MATERIA Y RELOJ DE GENERACIÓN.
  // El docente tiene que hacer una presentación por sesión —siete en varias
  // materias— y no había forma de saber cuáles ya hizo: terminaba repitiendo
  // una y dejando otra sin cubrir.
  // (10-sep) FORMATO DE SALIDA. El HTML es el que trae iconos, preguntas
  // que se revelan, cronómetro y guion del docente; nada de eso sobrevive
  // a un PDF. Por eso viene elegido de fábrica y la pantalla lo dice.
  String _formato = 'html_pdf'; // html_pdf | html | pdf_docx
  String _htmlDeck = '';
  bool _htmlCargando = false;
  bool _colocandoHtml = false;
  bool _generandoTarea = false;
  String _tareaHtmlSesion = '';
  bool _generandoCuestionario = false;
  String _cuestionarioHtmlSesion = '';
  bool _generandoCuadernillo = false;
  String _cuadernilloHtmlSesion = '';
  // (8-oct-2026) Actividad semanal en dos pasos (backend del 7-oct-2026, sin pantalla hasta
  // ahora): diapo_actividad_propuesta pide una idea corta y barata; diapo_actividad_crear
  // genera el material completo —con la idea ya aprobada o editada por el docente— y lo
  // coloca en el aula, en la semana que corresponde.
  bool _proponiendoActividad = false;
  bool _creandoActividad = false;
  String _actividadHtmlSesion = '';

  List<Map<String, dynamic>> _proyectos = [];
  int _versionesHechas = 0;
  bool _verCreadas = false;
  // Filtro de las presentaciones ya hechas: con varias materias y siete
  // sesiones cada una, la lista se vuelve larga rápido.
  final _filtroCreadas = TextEditingController();
  String _filtroMateria = ''; // '' = todas
  // (15-sep) BANCO. Las presentaciones de todos los docentes, para tomar una
  // en vez de generar otra vez la misma sesión y gastar una de las 20 del mes.
  // (15-sep) Buscador de la lista de materias: con toda la carga docente
  // había que bajar mucho para encontrar una.
  final _filtroMaterias = TextEditingController();
  String _filtroPrograma = ''; // '' = todos
  // (5-oct-2026) Vigencia de la materia: por omisión, solo las que están EN CURSO.
  String _filtroVigencia = 'curso'; // curso | proximas | terminadas | todas
  bool _verBanco = false;
  bool _cargandoBanco = false;
  List<Map<String, dynamic>> _banco = [];
  String _historial = '';
  Map<String, int> _sesionesPorMateria = {};
  Timer? _reloj;
  int _seg = 0;
  String _error = '';
  int _usoMes = 0, _tope = 20;

  // Material
  final _material = TextEditingController();
  final List<String> _archivosLeidos = [];

  // Controles
  int? _numDiapos; // null = las que hagan falta
  String _lenguaje = 'intermedio';
  String _profundidad = 'desarrollo';
  String _tipoSesion = 'exposición';
  int _duracion = 60;
  // Por omisión, las dos interacciones complejas: las sustitutivas (niveles 4 y 5).
  final Set<String> _niveles = {'sustitutivo_referencial', 'sustitutivo_no_referencial'};
  bool _sinPreguntas = false;
  final _sesion = TextEditingController();

  // (10-sep) LA PLANEACIÓN VALIDADA COMO MATERIAL.
  // El docente acababa de generar y validar la planeación de esa misma
  // materia —siete sesiones desarrolladas— y esta pantalla le pedía subir
  // material desde cero. El sistema ya tenía lo que necesitaba.
  List<Map<String, dynamic>> _planValidadas = [];
  bool _planCargando = false;
  String _planNota = '';
  // Gráficos, espacios de imagen y paleta
  String _graficos = 'pocos'; // ninguno · pocos · varios · todos · o un número
  final Set<String> _tiposGrafico = {'comparativa', 'linea_tiempo', 'proceso', 'mapa', 'tabla', 'ciclo', 'piramide', 'barras', 'pastel'};
  String _espaciosImagen = 'algunos'; // ninguno · algunos · varios
  String _paleta = 'clasica';
  String _plantilla = 'clasica';
  String _iconos = 'discretos'; // ninguno · discretos · destacados
  String _interactividad = 'media'; // ninguna · ligera · media · alta
  final Set<String> _tiposInteractivo = {'opcion_multiple', 'verdadero_falso', 'clasificar', 'ordenar', 'votacion', 'revelar', 'emparejar'};
  static const Map<String, List<String>> _interactivosInfo = {
    'opcion_multiple': ['Opción múltiple', 'una correcta, retroalimentación por opción'],
    'verdadero_falso': ['Verdadero o falso', 'afirmaciones con explicación'],
    'clasificar': ['Clasificar', 'arrastrar a categorías'],
    'ordenar': ['Ordenar', 'pasos revueltos que se acomodan'],
    'votacion': ['Votación', 'el grupo elige y ve la gráfica'],
    'revelar': ['Piensa y revela', 'pregunta abierta, respuesta oculta'],
    'emparejar': ['Emparejar', 'concepto con definición'],
  };

  static const Map<String, List<String>> _plantillasInfo = {
    'clasica': ['Clásica', 'Título arriba con raya dorada, filete rojo y oro, pregunta al margen.', 'clasica'],
    'editorial': ['Editorial', 'Barra lateral de color con el número grande; el título vive en la barra.', 'sobria'],
    'banda': ['Banda', 'Banda superior de color con el título en blanco; contenido limpio abajo.', 'clasica'],
    'nocturna': ['Nocturna', 'Fondo oscuro, título dorado. Para proyectar en sala con poca luz.', 'nocturna'],
    'minimal': ['Minimal', 'Mucho aire, título pequeño en dorado. La tipografía es la protagonista.', 'calida'],
  };

  static const Map<String, List<String>> _graficosInfo = {
    'comparativa': ['Comparativa', 'conceptos frente a frente'],
    'linea_tiempo': ['Línea de tiempo', 'hitos en orden'],
    'proceso': ['Proceso', 'pasos encadenados'],
    'ciclo': ['Ciclo', 'etapas que vuelven al inicio'],
    'mapa': ['Mapa conceptual', 'concepto central con ramas'],
    'tabla': ['Tabla', 'datos en filas y columnas'],
    'piramide': ['Pirámide', 'niveles jerárquicos'],
    'barras': ['Barras', 'magnitudes, solo si hay cifras'],
    'pastel': ['Pastel', 'proporciones, solo si hay porcentajes'],
  };
  static const Map<String, List<String>> _paletasInfo = {
    'clasica': ['Clásica', 'rojo y dorado sobre blanco; portada oscura'],
    'sobria': ['Sobria', 'tinta con acentos rojos; portada clara'],
    'calida': ['Cálida', 'crema y dorado; portada roja'],
    'nocturna': ['Nocturna', 'fondo oscuro, texto claro'],
  };

  // Proyecto
  String _modo = 'autonomo';
  String _id = '';
  List<Map<String, dynamic>> _preguntas = [];
  final Map<String, TextEditingController> _respuestas = {};
  Map<String, dynamic>? _esqueleto;
  Map<String, dynamic>? _presentacion;
  int _version = 0, _quedan = 3;
  final _retro = TextEditingController();
  // (30-sep) ID del curso de Moodle a mano — queda como ÚLTIMO RECURSO
  // dentro del modo «Otro curso» (ver abajo). Se ve en la URL del aula:
  // aula.cessum.mx/course/view.php?id=XXX
  final _courseIdManual = TextEditingController();

  // (7-oct-2026) CURSO DESTINO — selector resuelto, en vez de teclear el ID
  // a ciegas. Antes, si la materia no tenía aula o el ID estaba mal, el
  // docente no se enteraba hasta que «Hacer todo» ya llevaba un rato
  // corriendo. Ahora se resuelve ANTES de tocar el botón.
  String _cursoModo = 'sugerido'; // sugerido | mio | buscar
  Map<String, dynamic>? _cursoMateriaMia; // materia elegida en modo 'mio' (de _grupos)
  List<Map<String, dynamic>> _cursoCandidatos = []; // resultado de resolver: 0, 1 o varios
  int _cursoCandidatoElegido = 0; // índice dentro de _cursoCandidatos, si hay varios
  bool _cursoResolviendo = false;
  String _cursoResolverError = '';
  List<Map<String, dynamic>> _cursoTodos = []; // moodle_cursos, cargado bajo demanda (modo 'buscar')
  bool _cursoTodosCargando = false;
  final _cursoBuscarMioCtrl = TextEditingController();
  final _cursoBuscarCtrl = TextEditingController();

  static const Map<String, List<String>> _nivelesInfo = {
    'contextual': ['Contextual', 'reconocer, identificar · intrasituacional'],
    'suplementario': ['Suplementario', 'hacer, aplicar · intrasituacional'],
    'selector': ['Selector', 'elegir según un criterio · intrasituacional'],
    'sustitutivo_referencial': ['Sustitutivo referencial · compleja', 'hablar de lo que no está presente: abstraer, describir, explicar'],
    'sustitutivo_no_referencial': ['Sustitutivo no referencial · la más compleja', 'crear o transformar sistemas; resolver problemas conceptuales abstractos'],
  };

  @override
  void initState() {
    super.initState();
    _grupo = widget.grupoInicial;
    // Si viene de una planeación, el material ya está armado: se precarga y
    // el docente entra directo a los controles, sin volver a capturar nada.
    if ((widget.materialInicial ?? '').isNotEmpty) {
      _material.text = widget.materialInicial!;
      if (widget.sesionDePlaneacion > 0) {
        _sesion.text = '${widget.sesionDePlaneacion}';
      }
      // Los abridores planeados marcan el nivel de la sesión: la
      // presentación no debe bajarlo.
      if (RegExp(r'nivel [45]\)').hasMatch(widget.materialInicial!)) {
        _niveles
          ..clear()
          ..addAll(['sustitutivo_referencial', 'sustitutivo_no_referencial']);
      }
    }
    _cargar();
  }

  @override
  void dispose() {
    _reloj?.cancel();
    _filtroCreadas.dispose();
    _filtroMaterias.dispose();
    _courseIdManual.dispose();
    _cursoBuscarMioCtrl.dispose();
    _cursoBuscarCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      _correo = (await SessionStore.validEmail()) ?? '';
      final g = await http
          .get(Uri.parse('$guardianUrl?accion=mis_grupos&correo=${Uri.encodeComponent(_correo)}'))
          .timeout(const Duration(seconds: 30));
      final gd = jsonDecode(g.body) as Map<String, dynamic>;
      final p = await http
          .get(Uri.parse('$guardianUrl?accion=diapo_mis_proyectos&correo=${Uri.encodeComponent(_correo)}'))
          .timeout(const Duration(seconds: 30));
      final pd = jsonDecode(p.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _grupos = ((gd['grupos'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        // (10-sep) Los proyectos ya creados, para poder decir «3 de 7».
        _proyectos = ((pd['proyectos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _usoMes = int.tryParse('${pd['usoMes']}') ?? 0;
        _tope = int.tryParse('${pd['tope']}') ?? 20;
        if (_grupo != null) _paso = 1;
        _cargando = false;
      });
      if (_grupo != null) _resolverCurso(_grupo!);
    } catch (e) {
      if (mounted) setState(() { _cargando = false; _error = 'No se pudieron cargar tus materias: $e'; });
    }
  }

  /* El reloj no adivina cuánto falta —depende de la IA y no hay forma de
     saberlo—: cuenta lo transcurrido, que es lo único honesto y basta para
     que nadie crea que la pantalla se congeló. */
  void _arrancarReloj() {
    _seg = 0;
    _reloj?.cancel();
    _reloj = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seg++);
    });
  }

  void _pararReloj() {
    _reloj?.cancel();
    _reloj = null;
  }

  Widget _barraTrabajando(String queHace) {
    if (!_ocupado) return const SizedBox.shrink();
    final m = _seg ~/ 60, sg = _seg % 60;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF7EF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cessumGold.withValues(alpha: 0.45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(queHace,
                style: const TextStyle(
                    fontSize: 13.5, fontWeight: FontWeight.w700)),
          ),
          Text(m > 0 ? '$m min $sg s' : '$sg s',
              style: TextStyle(fontSize: 12, color: cessumMuted(context))),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: const LinearProgressIndicator(
            minHeight: 6,
            backgroundColor: Colors.black12,
            valueColor: AlwaysStoppedAnimation(cessumGold),
          ),
        ),
        const SizedBox(height: 6),
        Text('Puede tardar varios minutos. No cierres esta pantalla.',
            style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
      ]),
    );
  }

  /* Cuántas sesiones tiene la materia y cuántas presentaciones ya existen.
     El total sale del grupo (dosificación); lo creado, de los proyectos. */
  String _avanceDe(Map<String, dynamic> g) {
    final mat = '${g['materia'] ?? ''}'.toLowerCase().trim();
    final grp = '${g['grupo'] ?? ''}'.toLowerCase().trim();
    final hechas = _proyectos
        .where((p) =>
            '${p['materia'] ?? ''}'.toLowerCase().trim() == mat &&
            '${p['grupo'] ?? ''}'.toLowerCase().trim() == grp)
        .map((p) => '${p['sesion'] ?? 0}')
        .where((x) => x != '0')
        .toSet()
        .length;
    final total = int.tryParse('${g['sesiones'] ?? ''}') ?? 0;
    if (total <= 0) return hechas == 0 ? '' : '$hechas creada(s)';
    return '$hechas de $total presentaciones';
  }

  // (15-sep) VOLVER A UNA PRESENTACIÓN YA CREADA.
  // La pantalla siempre arrancaba de cero: para cambiar algo de una
  // presentación hecha había que rehacer todo el asistente y gastar otra de
  // las 20 generaciones del mes, aunque el material y el esqueleto ya
  // estuvieran aprobados. El Guardián guarda hasta tres versiones por
  // proyecto y sabe regenerar sin abrir uno nuevo; lo que faltaba era la
  // manera de llegar ahí.
  Future<void> _cargarBanco() async {
    if (_banco.isNotEmpty || _cargandoBanco) return;
    setState(() => _cargandoBanco = true);
    try {
      final r = await http
          .get(Uri.parse('$guardianUrl?accion=diapo_banco'
              '&z=${DateTime.now().millisecondsSinceEpoch}'))
          .timeout(const Duration(seconds: 45));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _banco = ((j['presentaciones'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargandoBanco = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargandoBanco = false);
    }
  }

  Future<void> _abrirProyecto(String id) async {
    setState(() { _ocupado = true; _error = ''; });
    try {
      final r = await http
          .get(Uri.parse('$guardianUrl?accion=diapo_obtener&id=${Uri.encodeComponent(id)}'
              '&z=${DateTime.now().millisecondsSinceEpoch}'))
          .timeout(const Duration(seconds: 45));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo abrir.');
      if (!mounted) return;
      setState(() {
        _id = '${j['id'] ?? ''}';
        _esqueleto = (j['esqueleto'] is Map)
            ? Map<String, dynamic>.from(j['esqueleto'] as Map)
            : null;
        _presentacion = (j['presentacion'] is Map)
            ? Map<String, dynamic>.from(j['presentacion'] as Map)
            : null;
        _version = int.tryParse('${j['version']}') ?? 1;
        _tomarVoz(j);
        _limpiarExportacion();   // (3-oct-2026) los enlaces eran de otro proyecto o de otra versión
        _versionesHechas = int.tryParse('${j['versiones']}') ?? 0;
        _historial = '${j['historial'] ?? ''}';
        // Cuántas versiones más admite: el tope del proyecto son tres.
        _quedan = 3 - _versionesHechas;
        if (_quedan < 0) _quedan = 0;
        _sesion.text = '${j['sesion'] ?? ''}';
        _grupo = {
          'materia': '${j['materia'] ?? ''}',
          'grupo': '${j['grupo'] ?? ''}',
          'programa': '${j['programa'] ?? ''}',
          'generacion': '${j['generacion'] ?? ''}',
          'clave': '${j['clave'] ?? ''}',
        };
        _htmlDeck = '';
        // Si ya tiene una versión, se abre directo en ella; si no, en el
        // esqueleto, que es donde se quedó.
        _paso = _presentacion != null ? 6 : 5;
        _ocupado = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ocupado = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  // (15-sep) BORRAR UNA VERSIÓN QUE NO SIRVIÓ.
  // El tope son tres por proyecto. Si la primera salió mal —el material iba
  // incompleto, la IA entendió otra cosa— esa versión ocupaba un lugar que no
  // se recuperaba: quedaban dos intentos para algo que nunca empezó.
  Future<void> _borrarVersion(int v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Borrar la versión $v?', style: const TextStyle(fontSize: 17)),
        content: const Text(
            'Se recupera ese lugar y podrás generar otra en su sitio. Las demás '
            'versiones se conservan. Esto no se puede deshacer.',
            style: TextStyle(fontSize: 13.5, height: 1.45)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() { _ocupado = true; _error = ''; });
    try {
      final j = await _post(
          {'accion': 'diapo_borrar_version', 'id': _id, 'version': v}, segundos: 45);
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo borrar.');
      if (!mounted) return;
      final quedan = int.tryParse('${j['versiones']}') ?? 0;
      setState(() {
        _versionesHechas = quedan;
        _quedan = 3 - quedan;
        if (_quedan < 0) _quedan = 0;
        _ocupado = false;
      });
      if (quedan > 0) {
        await _abrirProyecto(_id);   // recarga la versión que quedó vigente
      } else {
        setState(() { _presentacion = null; _version = 0; _paso = 5; _vozLaminas = []; _limpiarExportacion(); });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${j['nota'] ?? 'Versión borrada.'}'),
            backgroundColor: const Color(0xFF1E8E3E)));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ocupado = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  // Borrar el proyecto completo, para limpiar la lista de lo que no se usó.
  Future<void> _borrarProyecto(String id, String titulo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Borrar esta presentación?', style: TextStyle(fontSize: 17)),
        content: Text(
            '«$titulo» se borra con todas sus versiones. La generación del mes '
            'que ya se usó no se recupera. Esto no se puede deshacer.',
            style: const TextStyle(fontSize: 13.5, height: 1.45)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _ocupado = true);
    try {
      final j = await _post({'accion': 'diapo_borrar', 'id': id}, segundos: 45);
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo borrar.');
      if (!mounted) return;
      setState(() => _ocupado = false);
      await _cargar();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ocupado = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body, {int segundos = 120}) async {
    final r = await http
        .post(Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode({...body, 'actor': _correo}))
        .timeout(Duration(seconds: segundos));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  // ─────────────────────────────────────────── material
  Future<void> _subirArchivo() async {
    final input = html.FileUploadInputElement()
      ..accept = '.txt,.md,.pdf,.docx,.doc,.png,.jpg,.jpeg'
      ..multiple = true;
    input.click();
    await input.onChange.first;
    final files = input.files ?? [];
    for (final f in files) {
      final nombre = f.name.toLowerCase();
      final reader = html.FileReader();
      if (nombre.endsWith('.txt') || nombre.endsWith('.md')) {
        reader.readAsText(f);
        await reader.onLoad.first;
        _agregarTexto(f.name, reader.result as String);
      } else if (nombre.endsWith('.docx')) {
        // Word: el texto viene en word/document.xml dentro del zip. Se extrae
        // sin librerías: se quitan las etiquetas y quedan los párrafos.
        reader.readAsArrayBuffer(f);
        await reader.onLoad.first;
        final texto = await _textoDeDocx(reader.result as dynamic);
        _agregarTexto(f.name, texto);
      } else if (nombre.endsWith('.pdf')) {
        // El PDF lo lee la IA del lado del servidor sería ideal; aquí se pide
        // al docente que pegue el texto si el navegador no puede extraerlo.
        _agregarTexto(f.name, '[PDF adjunto: ${f.name}. Si el texto no aparece abajo, copia y pega el contenido del PDF en el cuadro.]');
      } else {
        _agregarTexto(f.name, '[Imagen: ${f.name}. Describe abajo qué contiene o qué quieres que se rescate de ella.]');
      }
    }
  }

  /* Word y PDF: leerlos en el navegador requiere librerías que la app no
     trae. En esta primera versión el docente pega el texto; el archivo se
     registra para que quede constancia de la fuente. La lectura automática
     de Word/PDF es la primera mejora de la siguiente fase. */
  Future<String> _textoDeDocx(dynamic buffer) async {
    return '[Word adjunto. Por ahora copia y pega su contenido en el cuadro de texto.]';
  }

  void _agregarTexto(String nombre, String texto) {
    setState(() {
      _archivosLeidos.add('$nombre (${texto.length} caracteres)');
      final actual = _material.text;
      _material.text = actual.isEmpty ? texto : '$actual\n\n--- $nombre ---\n$texto';
    });
  }

  // ─────────────────────────────────────────── pasos con IA
  // ─────────────────────────────────────────── PAQUETE COMPLETO
  /* (28-sep, recuperado 2-oct) EL PAQUETE COMPLETO DE LA ASIGNATURA.
     En el hub se anunciaba y no existía: el material se armaba sesión por
     sesión, a mano. Aquí se recorre la planeación VALIDADA y, para cada
     sesión, se hace lo mismo que el docente haría a mano —material de la
     sesión, proyecto, esqueleto, contenido— con los ajustes que eligió en
     «Controles», que valen para todas. Las sesiones que ya tienen una
     presentación de esta materia y grupo no se repiten. Si una falla, se
     sigue con las demás y al final se reintentan solo las que fallaron.
     (2-oct) Esta funcionalidad se había entregado el 28-sep pero se perdió
     al compilarse una versión anterior encima; se reconstruye aquí a
     partir del historial de esa entrega. */
  Map<String, dynamic>? _paqueteDe;
  List<Map<String, dynamic>> _paquete = [];
  bool _paqueteCorriendo = false;

  Map<String, dynamic> _parametros() => {
        'numDiapos': _numDiapos, 'lenguaje': _lenguaje, 'profundidad': _profundidad,
        'tipoSesion': _tipoSesion, 'duracion': _duracion,
        'niveles': _niveles.toList(), 'sinPreguntas': _sinPreguntas,
        'graficos': _graficos, 'tiposGrafico': _tiposGrafico.toList(),
        'espaciosImagen': _espaciosImagen, 'paleta': _paleta,
        'plantilla': _plantilla, 'iconos': _iconos,
        'interactividad': _interactividad, 'tiposInteractivo': _tiposInteractivo.toList(),
      };

  void _elegirPaquete(Map<String, dynamic> e) {
    setState(() {
      _paqueteDe = e;
      _paquete = [];
      _error = '';
      _paso = 2;
    });
  }

  // (2-oct-2026) Distingue un error TÉCNICO (algo reventó del lado del
  // Guardián: ReferenceError, TypeError, excepción de Apps Script, etc. —
  // nada que el docente pueda arreglar) de un error de CONTENIDO o de
  // negocio (material muy corto, cuota agotada, formato inesperado de la
  // IA — mensajes que el propio backend ya redacta en español claro para
  // quien lo lee). Solo el primer tipo detiene el paquete completo: un
  // error de contenido es normal que varíe sesión por sesión, un error
  // técnico casi siempre se repite igual en las que siguen.
  bool _esErrorTecnico(String msg) {
    final m = msg.toLowerCase();
    const marcas = [
      'referenceerror', 'typeerror', 'syntaxerror', 'rangeerror',
      'is not defined', 'is not a function', 'cannot read propert',
      'undefined is not', 'null is not an object', 'unexpected token',
      'script function not found', 'exceeded maximum execution time',
      'service invoked too many times', 'internal error',
    ];
    for (final marca in marcas) {
      if (m.contains(marca)) return true;
    }
    return false;
  }

  // El docente nunca debe ver el texto crudo de un error de programación.
  String _mensajeAmigableError(String msgTecnico) {
    return 'Hubo un problema técnico al generar esta sesión (no es culpa de '
        'tu material). El paquete se detuvo aquí para no repetir el mismo '
        'error varias veces. Avísale a Vicerrectoría — puedes tocar '
        '«Reintentar» más tarde, una vez que lo revisen.';
  }

  Future<void> _paqueteCompleto() async {
    final e = _paqueteDe;
    if (e == null || _grupo == null) return;
    final idPlan = '${e['idPlaneacion'] ?? ''}';
    setState(() { _ocupado = true; _error = ''; _paqueteCorriendo = true; _paso = 7; });
    _arrancarReloj();
    try {
      if (_paquete.isEmpty) {
        final j = await _post({'accion': 'planea_material_sesion', 'id': idPlan}, segundos: 120);
        if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo leer la planeación.');
        final ses = ((j['sesiones'] as List?) ?? [])
            .map((x) => Map<String, dynamic>.from(x as Map))
            .toList();
        if (ses.isEmpty) throw Exception('La planeación no trae sesiones.');
        final mat = '${_grupo?['materia'] ?? ''}'.toLowerCase().trim();
        final grp = '${_grupo?['grupo'] ?? ''}'.toLowerCase().trim();
        _paquete = ses.map((s) {
          final n = int.tryParse('${s['sesion']}') ?? 0;
          final ya = _proyectos.firstWhere(
              (p) =>
                  '${p['materia'] ?? ''}'.toLowerCase().trim() == mat &&
                  '${p['grupo'] ?? ''}'.toLowerCase().trim() == grp &&
                  (int.tryParse('${p['sesion']}') ?? 0) == n &&
                  (int.tryParse('${p['versiones']}') ?? 0) > 0,
              orElse: () => <String, dynamic>{});
          return <String, dynamic>{
            'sesion': n,
            'tema': '${s['tema'] ?? ''}',
            'id': ya.isEmpty ? '' : '${ya['id']}',
            'estado': ya.isEmpty ? 'pendiente' : 'existente',
            'error': '',
          };
        }).toList();
      }
      final porHacer = _paquete
          .where((x) => x['estado'] != 'lista' && x['estado'] != 'existente')
          .length;
      final libres = _tope - _usoMes;
      if (porHacer > libres) {
        throw Exception('El paquete necesita $porHacer generaciones y te quedan $libres este mes. '
            'Vicerrectoría puede ampliarte la cuota.');
      }
      var _detenidoPorFallaTecnica = false;
      for (final x in _paquete) {
        if (x['estado'] == 'lista' || x['estado'] == 'existente') continue;
        if (!mounted) return;
        // (2-oct-2026) Si una sesión anterior ya reventó por una falla
        // técnica (no de contenido), las que siguen ni se intentan: antes
        // el paquete seguía adelante sesión por sesión, cada una tardando
        // su minuto largo antes de fallar con el mismo error — 5 sesiones
        // podían tardar casi 10 minutos solo para terminar con 5 fallas
        // idénticas. Quedan marcadas "no_intentada", distinto de "error",
        // para que se note que no es que cada una fallara por su cuenta.
        if (_detenidoPorFallaTecnica) {
          setState(() => x['estado'] = 'no_intentada');
          continue;
        }
        setState(() { x['estado'] = 'trabajando'; x['error'] = ''; });
        try {
          await _paqueteSesion(idPlan, x);
          if (mounted) setState(() => x['estado'] = 'lista');
        } catch (err) {
          final msg = '$err'.replaceFirst('Exception: ', '');
          final tecnico = _esErrorTecnico(msg);
          if (mounted) {
            setState(() {
              x['estado'] = tecnico ? 'error_tecnico' : 'error';
              x['error'] = tecnico ? _mensajeAmigableError(msg) : msg;
            });
          }
          if (tecnico) _detenidoPorFallaTecnica = true;
        }
      }
      _pararReloj();
      if (mounted) setState(() { _ocupado = false; _paqueteCorriendo = false; });
    } catch (err) {
      _pararReloj();
      if (!mounted) return;
      setState(() {
        _ocupado = false;
        _paqueteCorriendo = false;
        _error = '$err'.replaceFirst('Exception: ', '');
        if (_paquete.isEmpty) _paso = 2;
      });
    }
  }

  Future<void> _paqueteSesion(String idPlan, Map<String, dynamic> x) async {
    final n = x['sesion'];
    final g = _grupo!;
    var id = '${x['id'] ?? ''}';
    if (id.isEmpty) {
      final m = await _post({'accion': 'planea_material_sesion', 'id': idPlan, 'sesion': '$n'}, segundos: 120);
      final material = '${m['material'] ?? ''}';
      if (m['ok'] != true || material.trim().isEmpty) {
        throw Exception(m['error'] ?? 'La sesión no trae contenido.');
      }
      final i = await _post({
        'accion': 'diapo_iniciar', 'correo': _correo,
        'materia': g['materia'] ?? '', 'clave': g['clave'] ?? '',
        'programa': g['programa'] ?? '', 'generacion': g['generacion'] ?? '', 'grupo': g['grupo'] ?? '',
        'sesion': '$n', 'modo': 'autonomo', 'material': material,
        'dePlaneacion': idPlan, 'parametros': _parametros(),
      });
      if (i['ok'] != true) throw Exception(i['error'] ?? 'No se pudo iniciar el proyecto.');
      id = '${i['id']}';
      x['id'] = id;
    }
    final es = await _post({'accion': 'diapo_esqueleto', 'id': id}, segundos: 300);
    if (es['ok'] != true) throw Exception(es['error'] ?? 'No llegó el esqueleto.');
    final ge = await _post({'accion': 'diapo_generar', 'id': id, 'esqueleto': es['esqueleto']}, segundos: 480);
    if (ge['ok'] != true) throw Exception(ge['error'] ?? 'No se pudo generar.');
    _usoMes += 1;
    x['diapositivas'] = ge['diapositivas'];
    x['version'] = ge['version'];
  }

  // ═══════════════════════════════════════════════════════════════════════
  // (2-oct-2026) EL PAQUETE AL AULA, DE UN JALÓN
  // ═══════════════════════════════════════════════════════════════════════
  // Hasta ahora, colocar en el aula, insertar el HTML y generar la tarea eran
  // botones de UNA sesión: con las cinco de Epistemología eran quince
  // pasos a mano, abriendo cada presentación. Aquí se hacen todos juntos,
  // sesión por sesión (cada una cae en su semana), con el estado de cada
  // acción a la vista.
  //
  // Reglas para que sea seguro repetirlo:
  //  · Todo es idempotente en el Guardián: lo ya colocado se actualiza, no se
  //    duplica (por eso se puede volver a tocar «Hacer todo» tras un fallo).
  //  · Un error TÉCNICO (algo reventó del lado del Guardián) o la falta de
  //    aula detienen todo: seguir solo repetiría el mismo fallo cinco veces.
  //  · Un tope de IA agotado solo frena las tareas; las presentaciones
  //    siguen, porque no usan IA.
  //  · Las tareas se diseñan JUNTAS: antes de la primera, un plan coordinado
  //    ve las cinco sesiones y decide formatos distintos y un hilo común.
  bool _loteAula = true;
  bool _loteHtml = true;
  bool _loteTareas = true;
  // (7-oct-2026) De forma ordinaria: encendidas de fábrica, igual que las tres de arriba.
  bool _loteCuestionario = true;
  bool _loteCuadernillo = true;
  bool _loteCorriendo = false;
  String _loteAviso = '';
  String _loteHilo = '';
  String _loteQue = '';
  final Map<String, Map<String, dynamic>> _lote = {};
  final Map<String, Map<String, dynamic>> _lotePlan = {}; // el plan coordinado de tareas, para reusarlo al reintentar

  List<Map<String, dynamic>> get _sesionesListas => _paquete
      .where((x) =>
          (x['estado'] == 'lista' || x['estado'] == 'existente') &&
          '${x['id'] ?? ''}'.isNotEmpty)
      .toList();

  Map<String, dynamic> _cuerpoLote(String accion, Map<String, dynamic> x) {
    final c = <String, dynamic>{'accion': accion, 'id': '${x['id']}'};
    final v = int.tryParse('${x['version'] ?? ''}') ?? 0;
    if (v > 0) c['version'] = '$v';
    final curso = _cursoIdFinal;
    if (curso.isNotEmpty) c['courseId'] = curso;
    return c;
  }

  // (7-oct-2026) CURSO DESTINO — resolución y selección.
  //
  // Fuente única de verdad: _cursoCandidatos. La resolvió el Guardián (modo
  // 'sugerido' o 'mio', buscando por asignación y por nombre) o la eligió
  // el propio docente de la lista de «Otro curso». El pegado a mano
  // (_courseIdManual) es el ÚLTIMO recurso, solo cuando no hay candidato.
  String get _cursoIdFinal {
    if (_cursoCandidatos.isNotEmpty) {
      final i = _cursoCandidatoElegido.clamp(0, _cursoCandidatos.length - 1);
      return '${_cursoCandidatos[i]['courseId'] ?? ''}';
    }
    if (_cursoModo == 'buscar') {
      final manual = _courseIdManual.text.trim();
      final m = RegExp(r'id=(\d+)').firstMatch(manual);
      if (m != null) return m.group(1)!;
      if (RegExp(r'^\d+$').hasMatch(manual)) return manual;
    }
    return '';
  }

  String get _cursoNombreFinal {
    if (_cursoCandidatos.isNotEmpty) {
      final i = _cursoCandidatoElegido.clamp(0, _cursoCandidatos.length - 1);
      return '${_cursoCandidatos[i]['nombre'] ?? ''}';
    }
    final id = _cursoIdFinal;
    return id.isEmpty ? '' : 'Curso ID $id (pegado a mano)';
  }

  String get _cursoUrlFinal {
    if (_cursoCandidatos.isNotEmpty) {
      final i = _cursoCandidatoElegido.clamp(0, _cursoCandidatos.length - 1);
      final u = '${_cursoCandidatos[i]['url'] ?? ''}';
      if (u.isNotEmpty) return u;
    }
    final id = _cursoIdFinal;
    return id.isEmpty ? '' : 'https://aula.cessum.mx/course/view.php?id=$id';
  }

  // Materias de _grupos para el modo «Otro de mis cursos»: las demás, con el mismo buscador de siempre.
  List<Map<String, dynamic>> get _cursoGruposParaElegir {
    final q = _cursoBuscarMioCtrl.text.trim().toLowerCase();
    final actual = _grupo;
    return _grupos.where((g) {
      if (actual != null && g == actual) return false;
      if (q.isEmpty) return true;
      final heno = '${g['materia'] ?? ''} ${g['programa'] ?? ''} ${g['generacion'] ?? ''} ${g['grupo'] ?? ''}'.toLowerCase();
      return q.split(RegExp(r'\s+')).every((w) => heno.contains(w));
    }).toList();
  }

  // Pide al Guardián el/los candidatos de aula para una materia. Sin IA, sin
  // colocar nada: solo lee la asignación (y, si hace falta, el nombre en
  // Moodle). Se llama ANTES de que el docente pueda tocar «Hacer todo».
  Future<void> _resolverCurso(Map<String, dynamic> g) async {
    setState(() {
      _cursoResolviendo = true;
      _cursoResolverError = '';
      _cursoCandidatos = [];
      _cursoCandidatoElegido = 0;
    });
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'diapo_aula_sugerida',
        'programa': '${g['programa'] ?? ''}',
        'generacion': '${g['generacion'] ?? ''}',
        'grupo': '${g['grupo'] ?? ''}',
        'materia': '${g['materia'] ?? ''}',
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 30));
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (j['ok'] != true) {
        setState(() { _cursoResolviendo = false; _cursoResolverError = '${j['error'] ?? 'No se pudo buscar el aula.'}'; });
        return;
      }
      final lista = ((j['candidatos'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      setState(() { _cursoResolviendo = false; _cursoCandidatos = lista; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _cursoResolviendo = false; _cursoResolverError = 'No se pudo conectar para buscar el aula.'; });
    }
  }

  // Lista completa de cursos de Moodle, para el modo «Otro curso». Se carga
  // una sola vez (bajo demanda) y el buscador filtra en el teléfono.
  Future<void> _cargarTodosLosCursos() async {
    setState(() => _cursoTodosCargando = true);
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=moodle_cursos'))
          .timeout(const Duration(seconds: 30));
      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      final lista = ((j['cursos'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      setState(() { _cursoTodos = lista; _cursoTodosCargando = false; });
    } catch (_) {
      if (mounted) setState(() => _cursoTodosCargando = false);
    }
  }

  // El componente compartido: se usa igual en el panel del paquete completo
  // y en el de una sola presentación.
  Widget _selectorCursoDestino() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Curso destino', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text('A dónde se va a colocar lo que generes.', style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          ChoiceChip(
            label: const Text('Curso sugerido', style: TextStyle(fontSize: 12)),
            selected: _cursoModo == 'sugerido',
            onSelected: (_) {
              setState(() => _cursoModo = 'sugerido');
              final g = _grupo;
              if (g != null && _cursoCandidatos.isEmpty && !_cursoResolviendo) _resolverCurso(g);
            },
          ),
          ChoiceChip(
            label: const Text('Otro de mis cursos', style: TextStyle(fontSize: 12)),
            selected: _cursoModo == 'mio',
            onSelected: (_) => setState(() { _cursoModo = 'mio'; _cursoCandidatos = []; _courseIdManual.clear(); }),
          ),
          ChoiceChip(
            label: const Text('Otro curso', style: TextStyle(fontSize: 12)),
            selected: _cursoModo == 'buscar',
            onSelected: (_) {
              setState(() { _cursoModo = 'buscar'; _cursoCandidatos = []; });
              if (_cursoTodos.isEmpty && !_cursoTodosCargando) _cargarTodosLosCursos();
            },
          ),
        ]),
        const SizedBox(height: 10),
        if (_cursoModo == 'sugerido') _cursoBloqueSugerido(_grupo),
        if (_cursoModo == 'mio') _cursoBloqueMio(),
        if (_cursoModo == 'buscar') _cursoBloqueBuscar(),
      ]),
    );
  }

  Widget _cursoBloqueSugerido(Map<String, dynamic>? g) {
    if (g == null) {
      return Text('Elige primero una materia.', style: TextStyle(fontSize: 12.5, color: cessumMuted(context)));
    }
    if (_cursoResolviendo) {
      return Row(children: [
        const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: 8),
        Text('Buscando el aula de «${g['materia']}»…', style: const TextStyle(fontSize: 12.5)),
      ]);
    }
    if (_cursoResolverError.isNotEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_cursoResolverError, style: const TextStyle(fontSize: 12.5, color: cessumRed)),
        const SizedBox(height: 4),
        TextButton(onPressed: () => _resolverCurso(g), child: const Text('Reintentar búsqueda', style: TextStyle(fontSize: 12.5))),
      ]);
    }
    if (_cursoCandidatos.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          'No encontré el aula de «${g['materia']}» en Moodle. Elige «Otro de mis cursos» u «Otro curso», '
          'o créala desde Agenda de profesores con «Aula + Meet».',
          style: TextStyle(fontSize: 12.5, color: cessumMuted(context), height: 1.4),
        ),
        const SizedBox(height: 4),
        TextButton(onPressed: () => _resolverCurso(g), child: const Text('Buscar de nuevo', style: TextStyle(fontSize: 12.5))),
      ]);
    }
    if (_cursoCandidatos.length == 1) return _cursoTarjeta(_cursoCandidatos.first);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Hay más de una aula que podría ser esta materia. Elige la correcta:',
          style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
      const SizedBox(height: 4),
      for (var i = 0; i < _cursoCandidatos.length; i++)
        RadioListTile<int>(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: i,
          groupValue: _cursoCandidatoElegido,
          onChanged: (v) => setState(() => _cursoCandidatoElegido = v ?? 0),
          title: Text('${_cursoCandidatos[i]['nombre']}', style: const TextStyle(fontSize: 13)),
        ),
    ]);
  }

  Widget _cursoTarjeta(Map<String, dynamic> c) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: cessumGold.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
      child: Row(children: [
        const Icon(Icons.school_outlined, size: 18, color: cessumGold),
        const SizedBox(width: 8),
        Expanded(child: Text('${c['nombre']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        TextButton(onPressed: () => _abrir('${c['url']}'), child: const Text('Abrir', style: TextStyle(fontSize: 12))),
      ]),
    );
  }

  Widget _cursoBloqueMio() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        controller: _cursoBuscarMioCtrl,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(
          isDense: true,
          prefixIcon: Icon(Icons.search, size: 18),
          hintText: 'Buscar materia, programa, generación o grupo',
          border: OutlineInputBorder(),
        ),
        style: const TextStyle(fontSize: 13),
      ),
      const SizedBox(height: 8),
      ..._cursoGruposParaElegir.take(8).map((g) => Card(
        margin: const EdgeInsets.only(bottom: 6),
        child: ListTile(
          dense: true,
          selected: _cursoMateriaMia == g,
          selectedTileColor: cessumGold.withValues(alpha: 0.10),
          title: Text('${g['materia']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          subtitle: Text('${g['programa']} · ${g['generacion']} · Grupo ${g['grupo']}', style: const TextStyle(fontSize: 11.5)),
          onTap: () { setState(() => _cursoMateriaMia = g); _resolverCurso(g); },
        ),
      )),
      if (_cursoGruposParaElegir.isEmpty)
        Text('No tienes otra materia que coincida con esa búsqueda.',
            style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
      if (_cursoMateriaMia != null) ...[
        const SizedBox(height: 8),
        _cursoBloqueSugerido(_cursoMateriaMia),
      ],
    ]);
  }

  Widget _cursoBloqueBuscar() {
    final q = _cursoBuscarCtrl.text.trim().toLowerCase();
    final lista = q.isEmpty
        ? const <Map<String, dynamic>>[]
        : _cursoTodos.where((c) {
            final nom = '${c['nombre'] ?? c['fullname'] ?? ''}'.toLowerCase();
            return nom.contains(q);
          }).take(12).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        controller: _cursoBuscarCtrl,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 18),
          hintText: _cursoTodosCargando ? 'Cargando lista de cursos…' : 'Buscar curso por nombre',
          border: const OutlineInputBorder(),
        ),
        style: const TextStyle(fontSize: 13),
      ),
      if (_cursoTodosCargando) ...[
        const SizedBox(height: 8),
        const LinearProgressIndicator(),
      ],
      if (lista.isNotEmpty) ...[
        const SizedBox(height: 8),
        ...lista.map((c) {
          final id = '${c['id'] ?? c['cursoId'] ?? ''}';
          final nombre = '${c['nombre'] ?? c['fullname'] ?? ''}';
          final elegido = _cursoCandidatos.length == 1 && '${_cursoCandidatos.first['courseId']}' == id;
          return Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              selected: elegido,
              selectedTileColor: cessumGold.withValues(alpha: 0.10),
              title: Text(nombre, style: const TextStyle(fontSize: 13)),
              onTap: () {
                setState(() {
                  _cursoCandidatos = [{
                    'courseId': id, 'nombre': nombre,
                    'url': 'https://aula.cessum.mx/course/view.php?id=$id',
                  }];
                  _cursoCandidatoElegido = 0;
                  _courseIdManual.clear();
                });
              },
            ),
          );
        }),
      ],
      const SizedBox(height: 10),
      Text('¿No lo encuentras? Pega el ID o la dirección del aula:',
          style: TextStyle(fontSize: 12, color: cessumMuted(context))),
      const SizedBox(height: 4),
      TextField(
        controller: _courseIdManual,
        onChanged: (_) => setState(() => _cursoCandidatos = []),
        decoration: const InputDecoration(
          isDense: true,
          hintText: 'Ej. 661 o aula.cessum.mx/course/view.php?id=661',
          border: OutlineInputBorder(),
        ),
        style: const TextStyle(fontSize: 13),
      ),
    ]);
  }

  String _temaDeSesion(String k) {
    for (final x in _paquete) {
      if ('${x['sesion']}' == k) return '${x['tema'] ?? ''}';
    }
    return '';
  }

  // Lo que, por su texto, no tiene caso reintentar con las demás sesiones.
  bool _esBloqueoDeIa(String msg) {
    final m = msg.toLowerCase();
    return m.contains('límite diario') || m.contains('cuota') || m.contains('clave de ia');
  }

  // Corre UNA acción de UNA sesión. Devuelve qué hacer con el resto:
  //   'sigue' → continuar · 'campo' → saltar esa acción en las demás sesiones
  //   'todo'  → detener todo el lote.
  Future<String> _loteAccion(
    String k,
    String campo,
    Future<Map<String, dynamic>> Function() llamada, {
    void Function(Map<String, dynamic> j)? alExito,
  }) async {
    final fila = _lote[k];
    if (fila == null) return 'sigue';
    if (mounted) setState(() => fila[campo] = 'trabajando');
    try {
      final j = await llamada();
      if (!mounted) return 'todo';
      if (j['sinAula'] == true) {
        setState(() {
          fila[campo] = 'error';
          fila['${campo}Msg'] = 'No encontré el aula de esta materia en Moodle.';
          _loteAviso = 'No encontré el aula de esta materia en Moodle. Pega arriba el ID del curso '
              '(lo ves en la dirección del aula: …/course/view.php?id=NNN) y vuelve a tocar «Hacer todo».';
        });
        return 'todo';
      }
      if (j['ok'] != true) {
        throw _ErrorConRef('${j['error'] ?? 'No se pudo completar.'}', '${j['referencia'] ?? ''}', j['sistemico'] == true);
      }
      setState(() {
        fila[campo] = 'ok';
        fila['${campo}Msg'] = '${j['nota'] ?? ''}';
        fila['${campo}Ref'] = '';
        // (3-oct) Si al exportar se completó u omitió alguna lámina, se dice cuál: la exportación ya no se detiene por eso.
        final av = j['avisosExportacion'];
        fila['${campo}Avisos'] = (av is List) ? av.map((e) => '$e').toList() : <String>[];
        if (alExito != null) alExito(j);
      });
      return 'sigue';
    } catch (err) {
      final conRef = err is _ErrorConRef ? err : null;
      final crudo = conRef != null ? conRef.mensaje : '$err'.replaceFirst('Exception: ', '');
      final tiempo = err is TimeoutException;
      final tecnico = conRef == null && (err is FormatException || _esErrorTecnico(crudo));
      final msg = tiempo
          ? 'Tardó más de lo esperado. Puede que sí se haya completado: revisa el aula antes de reintentar.'
          : tecnico
              ? 'Hubo un problema técnico (no es culpa de tu material). Se detuvo aquí para no repetirlo: '
                  'avísale a Vicerrectoría y toca «Reintentar solo lo que falló» cuando lo resuelvan.'
              : _suavizarError(crudo);
      if (mounted) {
        setState(() {
          fila[campo] = 'error';
          fila['${campo}Msg'] = msg;
          fila['${campo}Ref'] = conRef?.ref ?? '';
        });
      }
      if (tecnico || crudo.toLowerCase().contains('otro docente')) return 'todo';
      if (_esBloqueoDeIa(crudo)) return 'campo';
      // (3-oct) Un problema del sistema (p. ej. Moodle rechaza crear la tarea) se repetiría igual en cada sesión: no se insiste con
      // las demás —ni se gasta IA diseñando tareas que no se van a poder colocar—. Quedan «omitidas» y el reintento las retoma.
      if (conRef != null && conRef.sistemico) return 'campo';
      return 'sigue';
    }
  }

  Future<void> _loteEjecutar() async {
    final listas = _sesionesListas;
    if (listas.isEmpty || _loteCorriendo) return;
    if (!_loteAula && !_loteHtml && !_loteTareas && !_loteCuestionario && !_loteCuadernillo) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Elige al menos una cosa para llevar al aula.')));
      return;
    }
    if (_cursoIdFinal.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Elige primero el curso destino.')));
      return;
    }
    final sinPresentacion = _paquete.length - listas.length;
    final partes = <String>[
      if (_loteAula) '· La presentación (PDF dentro del aula)',
      if (_loteHtml) '· La presentación interactiva (HTML)',
      if (_loteTareas) '· Una tarea breve por sesión, con instrucciones, rúbrica y archivo editable',
      if (_loteCuestionario) '· Un cuestionario de repaso por sesión (sin valor de calificación, es autoestudio)',
      if (_loteCuadernillo) '· Un cuadernillo de estudio por sesión, con bibliografía precisa',
    ];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Llevar ${listas.length} sesión(es) al aula'),
        content: Text(
          'Sesión por sesión, cada una en su semana:\n\n${partes.join('\n')}\n\n'
          'Lo que ya esté en el aula se actualiza, no se duplica. '
          '${_loteTareas && listas.length >= 2 ? 'Las tareas se diseñan juntas, para que no se parezcan ni se repitan.\n' : ''}'
          '${sinPresentacion > 0 ? '\n$sinPresentacion sesión(es) sin presentación lista se omiten.\n' : ''}'
          '\nPuede tardar varios minutos. No cierres esta pantalla.',
          style: const TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hacer todo'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _loteCorriendo = true;
      _ocupado = true;
      _error = '';
      _loteAviso = '';
      _loteHilo = '';
      _loteQue = _loteTareas && listas.length >= 2 ? 'Coordinando las tareas del curso…' : 'Preparando…';
      _lote.clear();
      for (final x in listas) {
        _lote['${x['sesion']}'] = <String, dynamic>{
          'aula': _loteAula ? 'espera' : '',
          'html': _loteHtml ? 'espera' : '',
          'tarea': _loteTareas ? 'espera' : '',
          'cuestionario': _loteCuestionario ? 'espera' : '',
          'cuadernillo': _loteCuadernillo ? 'espera' : '',
        };
      }
    });
    _arrancarReloj();

    // 1) Plan coordinado de tareas. Es un extra: si falla, cada tarea se
    //    diseña por su cuenta y el lote sigue.
    final plan = <String, Map<String, dynamic>>{};
    if (_loteTareas && listas.length >= 2) {
      try {
        final j = await _post({
          'accion': 'diapo_tareas_plan',
          'ids': listas.map((x) => '${x['id']}').toList(),
        }, segundos: 180);
        if (j['ok'] == true) {
          _loteHilo = '${j['hilo'] ?? ''}';
          for (final t in ((j['plan'] as List?) ?? [])) {
            final m = Map<String, dynamic>.from(t as Map);
            plan['${m['sesion']}'] = m;
          }
        }
      } catch (_) {
        // Sin plan, las tareas salen igual.
      }
    }

    _lotePlan
      ..clear()
      ..addAll(plan);
    await _loteCorrer(listas, plan, regenerar: true);
  }

  // Recorre, sesión por sesión, lo que está en «espera»: presentación → interactiva → tarea. Lo que ya quedó «ok» NO se toca.
  Future<void> _loteCorrer(List<Map<String, dynamic>> listas, Map<String, Map<String, dynamic>> plan, {required bool regenerar}) async {
    // 2) Sesión por sesión: presentación → interactiva → tarea.
    var detener = false;
    final bloqueados = <String>{};
    for (final x in listas) {
      final k = '${x['sesion']}';
      final fila = _lote[k];
      if (fila == null) continue;
      for (final campo in const ['aula', 'html', 'tarea', 'cuestionario', 'cuadernillo']) {
        if (fila[campo] != 'espera') continue;
        if (!mounted) return;
        if (detener || bloqueados.contains(campo)) {
          setState(() => fila[campo] = 'omitida');
          continue;
        }
        setState(() {
          _loteQue = 'Sesión $k · ' +
              (campo == 'aula'
                  ? 'colocando la presentación…'
                  : campo == 'html'
                      ? 'colocando la presentación interactiva…'
                      : campo == 'tarea'
                          ? 'diseñando la tarea…'
                          : campo == 'cuestionario'
                              ? 'preparando el cuestionario de repaso…'
                              : 'escribiendo el cuadernillo de estudio…');
        });
        String r;
        if (campo == 'aula') {
          r = await _loteAccion(k, campo,
              () => _post(_cuerpoLote('diapo_colocar_aula', x), segundos: 300),
              alExito: (j) {
            fila['aulaUrl'] = '${j['aulaUrl'] ?? ''}';
            fila['semana'] = '${j['semana'] ?? ''}';
          });
        } else if (campo == 'html') {
          r = await _loteAccion(k, campo,
              () => _post(_cuerpoLote('diapo_html_colocar', x), segundos: 240));
        } else if (campo == 'tarea') {
          final c = _cuerpoLote('diapo_tarea_crear', x);
          // «Hacer todo» rediseña la tarea; el reintento coloca la MISMA ya diseñada (el servidor la recuerda 6 horas): no gasta IA ni cambia el texto.
          if (regenerar) c['regenerar'] = '1';
          final pl = plan[k];
          if (pl != null) {
            c['plan'] = pl;
            if (_loteHilo.isNotEmpty) c['hilo'] = _loteHilo;
          }
          r = await _loteAccion(k, campo, () => _post(c, segundos: 300), alExito: (j) {
            fila['tareaHtml'] = '${j['html'] ?? ''}';
            fila['tareaTitulo'] = '${j['titulo'] ?? ''}';
            fila['tareaUrl'] = '${j['tareaUrl'] ?? ''}';
          });
        } else if (campo == 'cuestionario') {
          final c = _cuerpoLote('diapo_cuestionario_crear', x);
          if (regenerar) c['regenerar'] = '1';
          r = await _loteAccion(k, campo, () => _post(c, segundos: 300), alExito: (j) {
            fila['cuestionarioPreguntas'] = '${j['preguntas'] ?? ''}';
          });
        } else {
          final c = _cuerpoLote('diapo_cuadernillo_crear', x);
          if (regenerar) c['regenerar'] = '1';
          r = await _loteAccion(k, campo, () => _post(c, segundos: 300), alExito: (j) {
            fila['cuadernilloSecciones'] = '${j['secciones'] ?? ''}';
            fila['cuadernilloReferencias'] = '${j['referencias'] ?? ''}';
          });
        }
        if (r == 'todo') detener = true;
        if (r == 'campo') bloqueados.add(campo);
      }
    }

    _pararReloj();
    if (!mounted) return;
    var hechas = 0, total = 0, fallas = 0;
    for (final f in _lote.values) {
      for (final c in const ['aula', 'html', 'tarea', 'cuestionario', 'cuadernillo']) {
        final e = '${f[c] ?? ''}';
        if (e.isEmpty) continue;
        total++;
        if (e == 'ok') hechas++;
        if (e == 'error') fallas++;
      }
    }
    setState(() {
      _ocupado = false;
      _loteCorriendo = false;
      _loteQue = '';
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(fallas == 0 && hechas == total
          ? 'Listo: las $total acciones quedaron en el aula.'
          : '$hechas de $total acciones listas. Las que no se pudieron quedan marcadas: toca «Reintentar solo lo que falló». Lo que ya está en el aula no se duplica.'),
    ));
  }

  // Cuántas piezas quedaron por reintentar: las que fallaron y las que se omitieron para no insistir con un problema del sistema.
  int get _lotePendientes {
    var n = 0;
    for (final f in _lote.values) {
      for (final c in const ['aula', 'html', 'tarea', 'cuestionario', 'cuadernillo']) {
        final e = '${f[c] ?? ''}';
        if (e == 'error' || e == 'omitida') n++;
      }
    }
    return n;
  }

  // (3-oct) REINTENTAR SOLO LO QUE FALLÓ. «Hacer todo» borra el estado y rehace todo (y rediseña las tareas con IA). Esto, en cambio, deja
  // intacto lo que ya está en el aula —no se vuelve a tocar ni a duplicar— y retoma solo lo que quedó con error u omitido.
  Future<void> _loteReintentar() async {
    if (_loteCorriendo || _lote.isEmpty) return;
    const nombres = {'aula': 'presentación', 'html': 'interactiva', 'tarea': 'tarea'};
    final claves = _lote.keys.toList()..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
    final pendientes = <String>[];
    for (final k in claves) {
      for (final c in const ['aula', 'html', 'tarea', 'cuestionario', 'cuadernillo']) {
        final e = '${_lote[k]?[c] ?? ''}';
        if (e == 'error' || e == 'omitida') pendientes.add('· Sesión $k · ${nombres[c]}');
      }
    }
    if (pendientes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay nada pendiente: todo lo elegido ya quedó en el aula.')));
      return;
    }
    if (_cursoIdFinal.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Elige primero el curso destino.')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Reintentar ${pendientes.length} pieza(s)'),
        content: Text(
          '${pendientes.join('\n')}\n\n'
          'Lo que ya quedó en el aula no se toca ni se duplica. Las tareas ya diseñadas se colocan tal cual, sin volver a diseñarlas.\n\n'
          'Puede tardar unos minutos. No cierres esta pantalla.',
          style: const TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reintentar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final sesiones = <String>{};
    setState(() {
      _loteCorriendo = true;
      _ocupado = true;
      _error = '';
      _loteAviso = '';
      _loteQue = 'Reintentando…';
      for (final k in claves) {
        final fila = _lote[k];
        if (fila == null) continue;
        for (final c in const ['aula', 'html', 'tarea', 'cuestionario', 'cuadernillo']) {
          final e = '${fila[c] ?? ''}';
          if (e == 'error' || e == 'omitida') {
            fila[c] = 'espera';
            fila['${c}Msg'] = '';
            fila['${c}Ref'] = '';
            sesiones.add(k);
          }
        }
      }
    });
    _arrancarReloj();
    final listas = _sesionesListas.where((x) => sesiones.contains('${x['sesion']}')).toList();
    await _loteCorrer(listas, Map<String, Map<String, dynamic>>.from(_lotePlan), regenerar: false);
  }

  // Defensa: si llegara un texto crudo de Moodle o de Google (servidor sin actualizar), el docente no debe verlo.
  String _suavizarError(String crudo) {
    final m = crudo.toLowerCase();
    if (m.contains('error escribiendo a la base de datos') || m.contains('moodle no pudo crear la tarea')) {
      return 'Moodle no aceptó crear la tarea en esta aula. Es un problema del sistema, no de tu material: avísale a Vicerrectoría.';
    }
    if (m.contains('has no text') || m.contains('slides_api')) {
      return 'Una lámina de esta presentación trae un elemento que no se pudo exportar. Avísale a Vicerrectoría.';
    }
    return crudo;
  }

  // El tema de una sesión viene del temario y puede ser larguísimo (y en planeaciones anteriores, cortado a media palabra a los 200 caracteres).
  // En pantalla se muestra completo hasta ~120 y después se corta en la última palabra completa.
  String _tituloCorto(String texto, [int max = 120]) {
    final s = texto.trim();
    if (s.length <= max) return s;
    var c = s.substring(0, max - 1);
    final sp = c.lastIndexOf(' ');
    if (sp > max * 0.6) c = c.substring(0, sp);
    return '${c.replaceAll(RegExp(r'[\s,;:.\-–—(]+$'), '')}…';
  }

  // Descarga un archivo generado, desde la app (no desde una página suelta).
  // El parámetro NO puede llamarse «html»: taparía el alias de dart:html.
  void _descargarArchivo(String nombre, String contenido) {
    try {
      final blob = html.Blob([contenido], 'text/html;charset=utf-8');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final a = html.AnchorElement(href: url)..download = nombre;
      html.document.body?.append(a);
      a.click();
      a.remove();
      html.Url.revokeObjectUrl(url);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo descargar el archivo.')));
    }
  }

  static const String _cuadernilloCabeza = r'''<!DOCTYPE html><html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Cuadernillo de tareas · {{MATERIA}}</title>
<style>body{margin:0;font-family:Montserrat,Arial,sans-serif;background:#F7F3EA}
.top{background:#B11D29;color:#fff;padding:14px 20px}.top h1{margin:0;font-size:17px}.top p{margin:3px 0 0;font-size:12px;opacity:.9}
.tabs{display:flex;gap:6px;flex-wrap:wrap;padding:10px 20px;background:#fff;border-bottom:1px solid #E4DACB}
.tabs button{border:1.5px solid #B11D29;background:#fff;color:#B11D29;border-radius:9px;padding:7px 12px;font:600 12.5px Montserrat,Arial;cursor:pointer}
.tabs button.on{background:#B11D29;color:#fff}
iframe{display:none;width:100%;height:calc(100vh - 118px);border:0}iframe.on{display:block}</style></head><body>
<div class="top"><h1>Cuadernillo de tareas</h1><p>{{MATERIA}} · para revisión del docente: así ve cada tarea el alumno</p></div>
<div class="tabs">{{BOTONES}}</div>{{MARCOS}}
<script>var B=[].slice.call(document.querySelectorAll('.tabs button')),F=[].slice.call(document.querySelectorAll('iframe'));
function ver(i){B.forEach(function(b,j){b.classList.toggle('on',i===j)});F.forEach(function(f,j){f.classList.toggle('on',i===j)});}
B.forEach(function(b,i){b.onclick=function(){ver(i)}});ver(0);</script></body></html>''';

  // Un solo archivo con las tareas de todas las sesiones, para que el docente
  // las revise (instrucciones, rúbrica y preguntas de defensa) sin abrir el aula.
  String _cuadernilloHtml() {
    const e = HtmlEscape(HtmlEscapeMode.attribute);
    final ks = _lote.keys
        .where((k) => '${_lote[k]?['tareaHtml'] ?? ''}'.isNotEmpty)
        .toList()
      ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
    final botones = StringBuffer();
    final marcos = StringBuffer();
    for (final k in ks) {
      final h = e.convert('${_lote[k]!['tareaHtml']}');
      botones.write('<button type="button">Sesión $k</button>');
      marcos.write('<iframe title="Sesión $k" srcdoc="$h"></iframe>');
    }
    return _cuadernilloCabeza
        .replaceAll('{{MATERIA}}', e.convert('${_grupo?['materia'] ?? ''}'))
        .replaceAll('{{BOTONES}}', botones.toString())
        .replaceAll('{{MARCOS}}', marcos.toString());
  }

  Widget _opcionLote(bool valor, ValueChanged<bool> alCambiar, String titulo, String detalle) {
    return CheckboxListTile(
      value: valor,
      onChanged: _loteCorriendo ? null : (v) => alCambiar(v ?? false),
      dense: true,
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: cessumRed,
      title: Text(titulo, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
      subtitle: Text(detalle, style: TextStyle(fontSize: 12, color: cessumMuted(context))),
    );
  }

  Widget _chipLote(String etiqueta, String estado) {
    final Color c = estado == 'ok'
        ? const Color(0xFF1E8E3E)
        : estado == 'error'
            ? cessumRed
            : estado == 'trabajando'
                ? cessumGold
                : cessumMuted(context);
    final IconData ic = estado == 'ok'
        ? Icons.check_circle
        : estado == 'error'
            ? Icons.error_outline
            : estado == 'trabajando'
                ? Icons.hourglass_top
                : estado == 'omitida'
                    ? Icons.remove_circle_outline
                    : Icons.schedule;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(ic, size: 13, color: c),
        const SizedBox(width: 4),
        Text(etiqueta, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
      ]),
    );
  }

  Widget _filaLote(String k) {
    final f = _lote[k]!;
    final chips = <Widget>[
      if ('${f['aula']}'.isNotEmpty) _chipLote('Presentación', '${f['aula']}'),
      if ('${f['html']}'.isNotEmpty) _chipLote('Interactiva', '${f['html']}'),
      if ('${f['tarea']}'.isNotEmpty) _chipLote('Tarea', '${f['tarea']}'),
      if ('${f['cuestionario']}'.isNotEmpty) _chipLote('Cuestionario', '${f['cuestionario']}'),
      if ('${f['cuadernillo']}'.isNotEmpty) _chipLote('Cuadernillo', '${f['cuadernillo']}'),
    ];
    final errores = <String>[
      for (final c in const ['aula', 'html', 'tarea', 'cuestionario', 'cuadernillo'])
        if ('${f[c]}' == 'error' && '${f['${c}Msg'] ?? ''}'.isNotEmpty) '${f['${c}Msg']}',
    ];
    final tieneTarea = '${f['tareaHtml'] ?? ''}'.isNotEmpty;
    final aulaUrl = '${f['aulaUrl'] ?? ''}';
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('Sesión $k · ${_tituloCorto(_temaDeSesion(k))}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ),
            if (tieneTarea)
              TextButton(
                onPressed: () => _descargarArchivo('actividad_sesion$k.html', '${f['tareaHtml']}'),
                child: const Text('Descargar tarea', style: TextStyle(fontSize: 12)),
              ),
            if (aulaUrl.isNotEmpty)
              TextButton(
                onPressed: () => _abrir(aulaUrl),
                child: const Text('Ver aula', style: TextStyle(fontSize: 12)),
              ),
          ]),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 4, children: chips),
          if ('${f['tareaTitulo'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Tarea: ${f['tareaTitulo']}',
                style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
          ],
          for (final m in errores)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(m, style: const TextStyle(fontSize: 12, color: cessumRed, height: 1.35)),
            ),
          // (3-oct) Láminas que se completaron u omitieron al exportar: se dice cuáles, sin que la exportación se detenga.
          for (final c in const ['aula', 'html', 'tarea', 'cuestionario', 'cuadernillo'])
            if ('${f[c]}' == 'ok' && ((f['${c}Avisos'] as List?) ?? const []).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Al preparar la presentación: ${((f['${c}Avisos'] as List).take(2)).join(' · ')}'
                  '${(f['${c}Avisos'] as List).length > 2 ? ' · y ${(f['${c}Avisos'] as List).length - 2} más' : ''}',
                  style: TextStyle(fontSize: 11.5, color: cessumMuted(context), height: 1.35),
                ),
              ),
        ]),
      ),
    );
  }

  Widget _panelLote() {
    final listas = _sesionesListas;
    if (listas.isEmpty) return const SizedBox.shrink();
    final claves = _lote.keys.toList()
      ..sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
    final hayTareas = _lote.values.any((f) => '${f['tareaHtml'] ?? ''}'.isNotEmpty);
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cessumRed.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumRed.withValues(alpha: 0.30)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Llevar el paquete al aula, de un jalón',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          'Cada sesión va a la semana que le corresponde. Lo que ya esté en el aula se '
          'actualiza, no se duplica.',
          style: TextStyle(fontSize: 12.5, height: 1.4, color: cessumMuted(context)),
        ),
        const SizedBox(height: 6),
        _opcionLote(_loteAula, (v) => setState(() => _loteAula = v), 'Presentaciones',
            'El PDF de cada sesión, visible dentro del aula.'),
        _opcionLote(_loteHtml, (v) => setState(() => _loteHtml = v), 'Presentaciones interactivas (HTML)',
            'Las que se recorren en pantalla, con actividades.'),
        _opcionLote(
            _loteTareas,
            (v) => setState(() => _loteTareas = v),
            'Tareas con instrucciones',
            'Una tarea breve por sesión, ligada a lo visto: anclada en evidencia propia del alumno, '
                'con rúbrica de 10 puntos, preguntas para defenderla y archivo editable. Se diseñan juntas.'),
        _opcionLote(
            _loteCuestionario,
            (v) => setState(() => _loteCuestionario = v),
            'Cuestionario de repaso',
            'Preguntas interactivas sobre lo visto en la sesión, con retroalimentación. Sin valor de '
                'calificación: es para que el alumno se autoevalúe por su cuenta.'),
        _opcionLote(
            _loteCuadernillo,
            (v) => setState(() => _loteCuadernillo = v),
            'Cuadernillo de estudio',
            'El texto que respalda la sesión: más desarrollo que la diapositiva, con el sustento teórico '
                'y bibliografía precisa. Elaboración: CESSUM.'),
        const SizedBox(height: 8),
        _selectorCursoDestino(),
        if (_cursoNombreFinal.isNotEmpty) ...[
          Text('Se colocará en: ${_cursoNombreFinal}',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: cessumRed)),
          const SizedBox(height: 10),
        ],
        Wrap(spacing: 10, runSpacing: 8, children: [
          _boton(_loteCorriendo ? 'Trabajando…' : 'Hacer todo (${listas.length} sesiones)',
              (_loteCorriendo || _cursoIdFinal.isEmpty) ? null : _loteEjecutar),
          if (!_loteCorriendo && _lotePendientes > 0)
            _boton('Reintentar solo lo que falló ($_lotePendientes)', _loteReintentar, sec: true),
          if (hayTareas && !_loteCorriendo)
            _boton('Descargar cuadernillo de tareas', () {
              final materiaTxt = '${_grupo?['materia'] ?? 'curso'}';
              final seguro = materiaTxt.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
              _descargarArchivo('cuadernillo_tareas_$seguro.html', _cuadernilloHtml());
            }, sec: true),
        ]),
        if (_loteAviso.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(_loteAviso, style: const TextStyle(fontSize: 12.5, color: cessumRed, height: 1.4)),
        ],
        if (_loteHilo.isNotEmpty && !_loteCorriendo) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cessumGold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('Hilo de las tareas: $_loteHilo',
                style: const TextStyle(fontSize: 12.5, height: 1.4)),
          ),
        ],
        if (claves.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final k in claves) _filaLote(k),
        ],
      ]),
    );
  }

  Widget _avisoPaqueteControles() {
    if (_paqueteDe == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: cessumRed.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumRed.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Paquete completo de la asignatura',
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
            'Estos ajustes se aplican a TODAS las sesiones de tu planeación validada. Se crea una '
            'presentación por sesión, con esqueleto automático; las que ya tengas de esta materia y '
            'grupo no se repiten. Cada sesión usa una de tus generaciones del mes '
            '(te quedan ${_tope - _usoMes}). Tarda unos minutos por sesión: no cierres la pantalla.',
            style: TextStyle(fontSize: 12.5, height: 1.4, color: cessumMuted(context))),
        TextButton(
          onPressed: () => setState(() { _paqueteDe = null; _paquete = []; }),
          child: const Text('Cancelar el paquete y hacer una sola presentación'),
        ),
      ]),
    );
  }

  Widget _botonPaquete(Map<String, dynamic> e) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 12),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
              foregroundColor: cessumRed, side: const BorderSide(color: cessumRed)),
          onPressed: _ocupado ? null : () => _elegirPaquete(e),
          icon: const Icon(Icons.library_books_outlined, size: 18),
          label: const Text('Generar el paquete completo de la asignatura'),
        ),
      );

  Widget _pasoPaquete() {
    final listas = _paquete
        .where((x) => x['estado'] == 'lista' || x['estado'] == 'existente')
        .length;
    // (2-oct-2026) Cuenta ambos tipos de falla — antes solo contaba
    // 'error', así que una falla técnica (estado nuevo 'error_tecnico')
    // no aparecía reflejada aquí ni habilitaba "Reintentar".
    final fallas = _paquete
        .where((x) => x['estado'] == 'error' || x['estado'] == 'error_tecnico')
        .length;
    final huboFallaTecnica = _paquete.any((x) => x['estado'] == 'error_tecnico');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _barraTrabajando(_loteCorriendo
          ? (_loteQue.isEmpty ? 'Llevando el paquete al aula…' : _loteQue)
          : 'Armando el paquete completo…'),
      Text('Paquete completo · ${_grupo?['materia'] ?? ''}',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(
          '$listas de ${_paquete.length} presentaciones listas'
          '${fallas > 0 ? ' · $fallas con falla' : ''}. '
          'Cuando termine, toca «Abrir» en cada una para revisarla y descargarla en PowerPoint o PDF.',
          style: TextStyle(fontSize: 13, color: cessumMuted(context))),
      // (2-oct-2026) Aviso aparte, más visible que una fila más en la
      // lista: explica POR QUÉ el paquete no llegó a 5 de 5 sin que el
      // docente tenga que abrir cada sesión para entender qué pasó.
      if (huboFallaTecnica && !_paqueteCorriendo) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cessumRed.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cessumRed.withValues(alpha: 0.35)),
          ),
          child: Text(
              'El paquete se detuvo antes de terminar por un problema técnico '
              '(no de tu material). Avísale a Vicerrectoría; cuando lo resuelvan, '
              'toca «Reintentar las que fallaron» para seguir desde donde se quedó.',
              style: TextStyle(fontSize: 12.5, height: 1.4, color: cessumRed)),
        ),
      ],
      const SizedBox(height: 10),
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: _paquete.isEmpty ? null : listas / _paquete.length,
          minHeight: 8,
          backgroundColor: cessumGold.withValues(alpha: 0.18),
          valueColor: const AlwaysStoppedAnimation(cessumRed),
        ),
      ),
      const SizedBox(height: 12),
      ..._paquete.map(_filaPaquete),
      const SizedBox(height: 12),
      if (!_paqueteCorriendo) _panelLote(),
      if (!_paqueteCorriendo && !_loteCorriendo)
        Wrap(spacing: 10, runSpacing: 8, children: [
          if (fallas > 0) _boton('Reintentar las que fallaron', _paqueteCompleto),
          _boton('Volver', () => setState(() { _paso = 1; }), sec: true),
        ]),
    ]);
  }

  Widget _filaPaquete(Map<String, dynamic> x) {
    final est = '${x['estado']}';
    final ok = est == 'lista' || est == 'existente';
    final esFalla = est == 'error' || est == 'error_tecnico';
    final Color c = ok
        ? const Color(0xFF1E8E3E)
        : esFalla
            ? cessumRed
            : est == 'trabajando'
                ? cessumGold
                : cessumMuted(context);
    final String detalle = est == 'lista'
        ? 'Lista${x['diapositivas'] != null ? ' · ${x['diapositivas']} diapositivas' : ''}'
        : est == 'existente'
            ? 'Ya tenías esta presentación: no se volvió a generar'
            : est == 'trabajando'
                ? 'Escribiendo esqueleto y contenido…'
                // (2-oct-2026) "no_intentada": el paquete se detuvo en una
                // sesión anterior por una falla técnica, y esta nunca
                // llegó a correr — distinto de "en espera" (que es el
                // estado normal antes de empezar).
                : est == 'no_intentada'
                    ? 'No se intentó: el paquete se detuvo antes de llegar aquí'
                    : esFalla
                        ? '${x['error']}'
                        : 'En espera';
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: est == 'trabajando'
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(
                ok
                    ? Icons.check_circle
                    : esFalla
                        ? Icons.error_outline
                        : est == 'no_intentada'
                            ? Icons.pause_circle_outline
                            : Icons.schedule,
                color: c),
        title: Text('Sesión ${x['sesion']} · ${_tituloCorto('${x['tema'] ?? ''}')}',
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
        subtitle: Text(detalle, style: TextStyle(fontSize: 12, color: esFalla ? cessumRed : cessumMuted(context))),
        trailing: (ok && '${x['id'] ?? ''}'.isNotEmpty && !_paqueteCorriendo)
            ? TextButton(onPressed: () => _abrirProyecto('${x['id']}'), child: const Text('Abrir'))
            : null,
      ),
    );
  }

  Future<void> _iniciar() async {
    setState(() { _ocupado = true; _error = ''; }); _arrancarReloj();
    try {
      final g = _grupo!;
      final j = await _post({
        'accion': 'diapo_iniciar', 'correo': _correo,
        'materia': g['materia'] ?? '', 'clave': g['clave'] ?? '',
        'programa': g['programa'] ?? '', 'generacion': g['generacion'] ?? '', 'grupo': g['grupo'] ?? '',
        'sesion': _sesion.text.trim(), 'modo': _modo, 'material': _material.text,
        // Le dice al motor que los abridores del material ya están
        // aprobados por el docente y no debe reinventarlos.
        'dePlaneacion': widget.dePlaneacion ?? '',
        'parametros': _parametros(),
      });
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo iniciar.');
      _id = '${j['id']}';
      if (_modo == 'colaborativo') {
        final q = await _post({'accion': 'diapo_preguntas', 'id': _id});
        if (q['ok'] != true) throw Exception(q['error'] ?? 'No llegaron las preguntas.');
        _preguntas = ((q['preguntas'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        for (final p in _preguntas) { _respuestas['${p['id']}'] = TextEditingController(); }
        setState(() { _paso = 4; _pararReloj(); _ocupado = false; });
      } else {
        await _pedirEsqueleto();
      }
    } catch (e) {
      setState(() { _pararReloj(); _ocupado = false; _error = '$e'.replaceFirst('Exception: ', ''); });
    }
  }

  Future<void> _pedirEsqueleto() async {
    setState(() { _ocupado = true; _error = ''; }); _arrancarReloj();
    try {
      final resp = _preguntas.map((p) => {
        'id': p['id'], 'pregunta': p['texto'], 'respuesta': _respuestas['${p['id']}']?.text.trim() ?? '',
      }).where((r) => (r['respuesta'] as String).isNotEmpty).toList();
      final j = await _post({'accion': 'diapo_esqueleto', 'id': _id, if (resp.isNotEmpty) 'respuestas': resp});
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No llegó el esqueleto.');
      // (8-oct-2026) Antes el cast a Map tronaba con un error de tipo en crudo si «esqueleto»
      // llegaba ausente o nulo pese a ok:true; ahora se avisa con un mensaje claro.
      if (j['esqueleto'] is! Map) throw Exception('El esqueleto no llegó completo. Intenta de nuevo.');
      setState(() { _esqueleto = Map<String, dynamic>.from(j['esqueleto'] as Map); _paso = 5; _pararReloj(); _ocupado = false; });
    } catch (e) {
      setState(() { _pararReloj(); _ocupado = false; _error = '$e'.replaceFirst('Exception: ', ''); });
    }
  }

  Future<void> _generar() async {
    setState(() { _ocupado = true; _error = ''; }); _arrancarReloj();
    try {
      final j = await _post({'accion': 'diapo_generar', 'id': _id, 'esqueleto': _esqueleto}, segundos: 480);
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo generar.');
      // (8-oct-2026) Igual que en _pedirEsqueleto: mensaje claro en vez de un error de tipo crudo.
      if (j['presentacion'] is! Map) throw Exception('La presentación no llegó completa. Intenta de nuevo.');
      setState(() {
        _presentacion = Map<String, dynamic>.from(j['presentacion'] as Map);
        _version = int.tryParse('${j['version']}') ?? 1;
        _tomarVoz(j); _limpiarExportacion();
        _quedan = int.tryParse('${j['quedan']}') ?? 0;
        _usoMes += 1;
        _paso = 6; _pararReloj(); _ocupado = false;
      });
    } catch (e) {
      setState(() { _pararReloj(); _ocupado = false; _error = '$e'.replaceFirst('Exception: ', ''); });
    }
  }

  Future<void> _revisar() async {
    if (_retro.text.trim().length < 10) {
      setState(() => _error = 'Escribe qué quieres cambiar: al menos una frase.');
      return;
    }
    setState(() { _ocupado = true; _error = ''; }); _arrancarReloj();
    try {
      final j = await _post({'accion': 'diapo_revisar', 'id': _id, 'retro': _retro.text.trim(), 'base': _version}, segundos: 480);
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo revisar.');
      // (8-oct-2026) Igual que en _pedirEsqueleto/_generar: mensaje claro en vez de un error crudo.
      if (j['presentacion'] is! Map) throw Exception('La presentación revisada no llegó completa. Intenta de nuevo.');
      setState(() {
        _presentacion = Map<String, dynamic>.from(j['presentacion'] as Map);
        _version = int.tryParse('${j['version']}') ?? _version + 1;
        _tomarVoz(j); _limpiarExportacion();
        _quedan = int.tryParse('${j['quedan']}') ?? 0;
        _usoMes += 1; _retro.clear(); _pararReloj(); _ocupado = false;
      });
    } catch (e) {
      setState(() { _pararReloj(); _ocupado = false; _error = '$e'.replaceFirst('Exception: ', ''); });
    }
  }

  /* (9-sep) EXPORTAR DESDE LA APP, NO DESDE UNA PÁGINA SUELTA.
     Antes «Descargar» abría diapositivas.html en otra pestaña, un archivo
     HTML del servidor que armaba el PowerPoint en el navegador. Era la
     pieza que fallaba, y la que se pidió no volver a usar: lo que la app
     necesite generar se genera desde la app.
     Ahora el Guardián construye la presentación en Google Slides con la
     identidad CESSUM y de ahí saca el PDF y el PPTX. Los tres quedan en
     Drive, compartidos con el dominio, y aquí se muestran los tres enlaces. */
  Map<String, String> _exportado = {};
  bool _exportando = false;
  /* (3-oct-2026) VOZ DE LA LÁMINA. El Guardián devuelve en `vozLaminas` las láminas que todavía le hablan al docente («pide», «recoge»,
     «escribe en pantalla»…). Si hay alguna, se avisa arriba y «Reescribir para el grupo» la corrige EN SU LUGAR, sin gastar versión ni cuota
     (diapo_revisar con voz=1). `_fuentesPdf` trae las fuentes que el PDF incrustó, para decir si salió en Montserrat. */
  List<int> _vozLaminas = [];
  bool _reescribiendoVoz = false;
  List<String> _fuentesPdf = [];
  List<String> _avisosExport = [];
  void _tomarVoz(Map<String, dynamic> j) {
    final l = j['vozLaminas'];
    _vozLaminas = (l is List) ? l.map((e) => int.tryParse('$e') ?? 0).where((e) => e > 0).toList() : <int>[];
  }
  void _limpiarExportacion() { _exportado = {}; _fuentesPdf = []; _avisosExport = []; }

  Future<void> _reescribirVoz() async {
    if (_id.isEmpty || _version < 1 || _reescribiendoVoz) return;
    setState(() { _reescribiendoVoz = true; _error = ''; });
    try {
      final j = await _post({'accion': 'diapo_revisar', 'id': _id, 'version': '$_version', 'voz': '1'}, segundos: 300);
      if (!mounted) return;
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo reescribir.');
      setState(() {
        if (j['presentacion'] is Map) _presentacion = Map<String, dynamic>.from(j['presentacion'] as Map);
        _tomarVoz(j);
        _limpiarExportacion();   // el PowerPoint y el PDF anteriores ya no corresponden al texto nuevo
        _reescribiendoVoz = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${j['nota'] ?? 'Reescrita.'}'), duration: const Duration(seconds: 8)));
    } catch (e) {
      setState(() { _reescribiendoVoz = false; _error = '$e'.replaceFirst('Exception: ', ''); });
    }
  }

  Widget _avisoVoz() {
    if (_vozLaminas.isEmpty) return const SizedBox.shrink();
    final ls = _vozLaminas.join(', ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFFFF4E5), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE0A24D))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.record_voice_over_outlined, size: 18, color: Color(0xFF9A5B00)),
          const SizedBox(width: 8),
          Expanded(child: Text(_vozLaminas.length == 1 ? 'La lámina $ls le habla al docente, no al grupo' : 'Las láminas $ls le hablan al docente, no al grupo',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
        ]),
        const SizedBox(height: 6),
        Text('Traen indicaciones de conducción («pide a…», «recoge respuestas», «escribe en pantalla»). Al reescribirlas, la lámina queda dirigida '
            'a los estudiantes y la indicación pasa a las notas del presentador. No cuenta como otra generación: tu cuota y tus versiones quedan igual.',
            style: TextStyle(fontSize: 12, height: 1.4, color: cessumMuted(context))),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF9A5B00), foregroundColor: Colors.white),
          onPressed: _reescribiendoVoz ? null : _reescribirVoz,
          icon: _reescribiendoVoz
              ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.auto_fix_high, size: 18),
          label: Text(_reescribiendoVoz ? 'Reescribiendo… (1 a 3 min)' : 'Reescribir para el grupo (no gasta cuota)'),
        ),
      ]),
    );
  }

  Future<void> _previsualizarHtml() async {
    if (_id.isEmpty || _version < 1) return;
    setState(() { _htmlCargando = true; _error = ''; });
    try {
      final j = await _post({'accion': 'diapo_html', 'id': _id, 'version': '$_version'},
          segundos: 120);
      if (!mounted) return;
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo generar el HTML.');
      setState(() { _htmlDeck = '${j['html'] ?? ''}'; _htmlCargando = false; });
      _abrirHtmlEnPestana(_htmlDeck);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _htmlCargando = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  /* Se abre en una pestaña propia y no en un diálogo: una presentación a
     pantalla completa dentro de un modal no se puede juzgar, y aquí de lo
     que se trata es de verla como la verá el grupo. */
  // El parámetro NO puede llamarse «html»: taparía el alias del import
  // dart:html y el compilador buscaría Blob dentro de un String.
  void _abrirHtmlEnPestana(String contenido) {
    try {
      final blob = html.Blob([contenido], 'text/html;charset=utf-8');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.window.open(url, '_blank');
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No se pudo abrir la vista previa. Revisa el bloqueador de ventanas.'),
      ));
    }
  }

  Future<void> _generarTarea({bool soloArchivo = false}) async {
    if (_id.isEmpty || _version < 1) return;
    final ok = soloArchivo ? true : await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Generar tarea de esta sesión'),
        content: const Text(
          'Se diseña una tarea breve basada en lo que se vio en esta presentación: pocos pasos, '
          'anclada en evidencia que solo el alumno tiene, con rúbrica de 10 puntos, preguntas '
          'para defenderla en la siguiente sesión y un archivo que el alumno completa y '
          'guarda con un botón. Se crea en el Aula CESSUM, en la semana correspondiente, con '
          'las instrucciones escritas.\n\n'
          'La fecha de apertura y de cierre son las de inicio y término de la materia completa.\n\n'
          'Si ya habías generado la tarea de esta sesión, se actualiza.',
          style: TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Generar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() { _generandoTarea = true; _error = ''; });
    try {
      final cuerpo = <String, dynamic>{
        'accion': 'diapo_tarea_crear', 'id': _id, 'version': '$_version'
      };
      if (soloArchivo) cuerpo['soloVista'] = '1';
      if (_cursoIdFinal.isNotEmpty) cuerpo['courseId'] = _cursoIdFinal;
      final j = await _post(cuerpo, segundos: 240);
      if (!mounted) return;
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo generar la tarea.');
      final htmlTarea = '${j['html'] ?? ''}';
      setState(() {
        _generandoTarea = false;
        if (htmlTarea.isNotEmpty) _tareaHtmlSesion = htmlTarea;
      });
      if (soloArchivo && htmlTarea.isNotEmpty) {
        _descargarArchivo('actividad_sesion${_sesion.text.trim()}.html', htmlTarea);
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${j['nota'] ?? 'Tarea generada en el aula.'}'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _generandoTarea = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }


  Future<void> _generarCuestionario({bool soloArchivo = false}) async {
    if (_id.isEmpty || _version < 1) return;
    final ok = soloArchivo ? true : await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cuestionario de repaso de esta sesión'),
        content: const Text(
          'Se escriben preguntas interactivas sobre lo que se vio en esta presentación, con '
          'retroalimentación en cada una. NO TIENE VALOR DE CALIFICACIÓN: es para que el alumno '
          'se autoevalúe por su cuenta. Se coloca en el Aula CESSUM, en la semana correspondiente, '
          'marcado como no calificable.\\n\\n'
          'Si ya lo habías generado para esta sesión, se actualiza.',
          style: TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Generar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() { _generandoCuestionario = true; _error = ''; });
    try {
      final cuerpo = <String, dynamic>{
        'accion': 'diapo_cuestionario_crear', 'id': _id, 'version': '$_version'
      };
      if (soloArchivo) cuerpo['soloVista'] = '1';
      if (_cursoIdFinal.isNotEmpty) cuerpo['courseId'] = _cursoIdFinal;
      final j = await _post(cuerpo, segundos: 240);
      if (!mounted) return;
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo generar el cuestionario.');
      final htmlQ = '${j['html'] ?? ''}';
      setState(() {
        _generandoCuestionario = false;
        if (htmlQ.isNotEmpty) _cuestionarioHtmlSesion = htmlQ;
      });
      if (soloArchivo && htmlQ.isNotEmpty) {
        _descargarArchivo('cuestionario_sesion${_sesion.text.trim()}.html', htmlQ);
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${j['nota'] ?? 'Cuestionario generado.'}'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _generandoCuestionario = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _generarCuadernillo({bool soloArchivo = false}) async {
    if (_id.isEmpty || _version < 1) return;
    final ok = soloArchivo ? true : await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cuadernillo de estudio de esta sesión'),
        content: const Text(
          'Se escribe el texto que respalda la sesión: más desarrollo que la diapositiva, el '
          'sustento teórico y una bibliografía precisa (ligada a la literatura que ya subiste '
          'para esta materia, cuando la tienes). Lleva la elaboración de CESSUM al pie. Se '
          'coloca en el Aula CESSUM, en la semana correspondiente.\\n\\n'
          'Si ya lo habías generado para esta sesión, se actualiza.',
          style: TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Generar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() { _generandoCuadernillo = true; _error = ''; });
    try {
      final cuerpo = <String, dynamic>{
        'accion': 'diapo_cuadernillo_crear', 'id': _id, 'version': '$_version'
      };
      if (soloArchivo) cuerpo['soloVista'] = '1';
      if (_cursoIdFinal.isNotEmpty) cuerpo['courseId'] = _cursoIdFinal;
      final j = await _post(cuerpo, segundos: 240);
      if (!mounted) return;
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo generar el cuadernillo.');
      final htmlC = '${j['html'] ?? ''}';
      setState(() {
        _generandoCuadernillo = false;
        if (htmlC.isNotEmpty) _cuadernilloHtmlSesion = htmlC;
      });
      if (soloArchivo && htmlC.isNotEmpty) {
        _descargarArchivo('cuadernillo_estudio_sesion${_sesion.text.trim()}.html', htmlC);
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${j['nota'] ?? 'Cuadernillo generado.'}'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _generandoCuadernillo = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  /* (8-oct-2026) ACTIVIDAD SEMANAL EN DOS PASOS — pantalla para diapo_actividad_propuesta y
     diapo_actividad_crear (backend del 7-oct-2026). A diferencia de la tarea, el cuestionario y
     el cuadernillo (un clic, confirmar, generar), la actividad pide primero una idea corta y
     barata que el docente aprueba o edita, y solo entonces se genera el material completo y se
     coloca en el aula. Paso 1: pedir la propuesta. */
  Future<void> _actividadSemanal() async {
    if (_id.isEmpty || _version < 1) return;
    setState(() { _proponiendoActividad = true; _error = ''; });
    Map<String, dynamic> prop;
    try {
      prop = await _post({'accion': 'diapo_actividad_propuesta', 'id': _id, 'version': '$_version'}, segundos: 90);
    } catch (e) {
      prop = {'ok': false, 'error': '$e'.replaceFirst('Exception: ', '')};
    }
    if (!mounted) return;
    setState(() => _proponiendoActividad = false);
    if (prop['ok'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${prop['error'] ?? 'No se pudo proponer la actividad.'}')));
      return;
    }
    await _editarYCrearActividad('${prop['titulo'] ?? ''}', '${prop['descripcion'] ?? ''}');
  }

  // Paso 2: el docente ve la propuesta, la edita (o pide otra), y decide vista previa o colocar.
  Future<void> _editarYCrearActividad(String tituloInicial, String descripcionInicial) async {
    final tCtrl = TextEditingController(text: tituloInicial);
    final dCtrl = TextEditingController(text: descripcionInicial);
    final accion = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        var regenerando = false;
        return AlertDialog(
          title: const Text('Actividad de la semana'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  'Idea propuesta por la IA a partir de lo que se vio en esta sesión. Edítala o '
                  'escribe la tuya antes de generarla completa: instrucciones y piezas interactivas.',
                  style: TextStyle(fontSize: 12.5, color: cessumMuted(ctx)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tCtrl,
                  maxLength: 90,
                  decoration: const InputDecoration(labelText: 'Título', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: dCtrl,
                  minLines: 2, maxLines: 5, maxLength: 420,
                  decoration: const InputDecoration(labelText: 'Descripción', border: OutlineInputBorder()),
                ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Cancelar')),
            TextButton(
              onPressed: regenerando ? null : () async {
                setD(() => regenerando = true);
                try {
                  final p2 = await _post({'accion': 'diapo_actividad_propuesta', 'id': _id, 'version': '$_version'}, segundos: 90);
                  if (p2['ok'] == true) {
                    tCtrl.text = '${p2['titulo'] ?? tCtrl.text}';
                    dCtrl.text = '${p2['descripcion'] ?? dCtrl.text}';
                  }
                } catch (_) {}
                setD(() => regenerando = false);
              },
              child: Text(regenerando ? 'Pidiendo otra idea…' : 'Otra idea'),
            ),
            OutlinedButton(onPressed: () => Navigator.pop(ctx, 'vista'), child: const Text('Vista previa')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, 'colocar'),
              child: const Text('Colocar en el aula'),
            ),
          ],
        );
      }),
    );
    final titulo = tCtrl.text.trim();
    final descripcion = dCtrl.text.trim();
    tCtrl.dispose();
    dCtrl.dispose();
    if (accion == null || !mounted) return;
    if (titulo.isEmpty || descripcion.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Falta el título o la descripción de la actividad.')));
      return;
    }
    await _crearActividad(titulo, descripcion, soloVista: accion == 'vista');
  }

  // Paso 3: genera el material completo (o solo la vista previa) y, si no es vista previa,
  // la coloca en el aula en la semana que corresponde — con el mismo manejo de "sin aula" y
  // "semana protegida" que ya usan _colocarEnAula / diapo_colocar_aula.
  Future<void> _crearActividad(String titulo, String descripcion, {required bool soloVista, bool desbloquear = false}) async {
    setState(() { _creandoActividad = true; _error = ''; });
    try {
      final cuerpo = <String, dynamic>{
        'accion': 'diapo_actividad_crear', 'id': _id, 'version': '$_version',
        'titulo': titulo, 'descripcion': descripcion,
      };
      if (soloVista) cuerpo['soloVista'] = '1';
      if (desbloquear) cuerpo['desbloquear'] = '1';
      if (_cursoIdFinal.isNotEmpty) cuerpo['courseId'] = _cursoIdFinal;
      final j = await _post(cuerpo, segundos: 240);
      if (!mounted) return;
      if (j['sinAula'] == true) {
        setState(() => _creandoActividad = false);
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Esta materia no tiene aula'),
            content: Text('${j['error'] ?? ''}', style: const TextStyle(height: 1.4)),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido'))],
          ),
        );
        return;
      }
      if (j['protegida'] == true) {
        setState(() => _creandoActividad = false);
        final sigue = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Semana protegida'),
            content: Text('${j['error'] ?? 'Esa semana ya tiene material puesto a mano por el docente.'}',
                style: const TextStyle(height: 1.4)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Colocar igual'),
              ),
            ],
          ),
        );
        if (sigue != true || !mounted) return;
        await _crearActividad(titulo, descripcion, soloVista: false, desbloquear: true);
        return;
      }
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo generar la actividad.');
      final htmlAct = '${j['html'] ?? ''}';
      setState(() {
        _creandoActividad = false;
        if (htmlAct.isNotEmpty) _actividadHtmlSesion = htmlAct;
      });
      if (soloVista && htmlAct.isNotEmpty) {
        _descargarArchivo('actividad_semanal_sesion${_sesion.text.trim()}.html', htmlAct);
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${j['nota'] ?? (soloVista ? 'Vista previa descargada.' : 'Actividad colocada en el aula.')}'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() { _creandoActividad = false; _error = '$e'.replaceFirst('Exception: ', ''); });
    }
  }

  Future<void> _colocarHtmlEnAula() async {
    if (_id.isEmpty || _version < 1) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Colocar en el Aula CESSUM'),
        content: const Text(
          'La presentación interactiva se agrega como recurso en la semana que '
          'corresponde a esta sesión. Los alumnos podrán recorrerla desde el aula.\n\n'
          'Si ya habías colocado esta misma presentación, se reemplaza por la '
          'versión actual.',
          style: TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Colocar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() { _colocandoHtml = true; _error = ''; });
    try {
      final cuerpo = <String, dynamic>{
        'accion': 'diapo_html_colocar', 'id': _id, 'version': '$_version'
      };
      // Si el docente ya previsualizó, se manda ese HTML: puede haberlo
      // ajustado y lo que se coloca debe ser lo que él vio.
      if (_htmlDeck.isNotEmpty) cuerpo['html'] = _htmlDeck;
      if (_cursoIdFinal.isNotEmpty) cuerpo['courseId'] = _cursoIdFinal;
      final j = await _post(cuerpo, segundos: 240);
      if (!mounted) return;
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo colocar.');
      setState(() => _colocandoHtml = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${j['nota'] ?? 'Colocada en el aula.'}'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _colocandoHtml = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  Widget _opcionFormato(String valor, String titulo, String detalle,
      {bool recomendado = false}) {
    final sel = _formato == valor;
    return InkWell(
      onTap: () => setState(() => _formato = valor),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: sel ? cessumRed.withValues(alpha: 0.07) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: sel ? cessumRed.withValues(alpha: 0.5) : Colors.black12,
              width: sel ? 1.4 : 1),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(sel ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 20, color: sel ? cessumRed : cessumMuted(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(titulo,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
                if (recomendado) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: cessumGold.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text('Recomendado',
                        style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: cessumGold)),
                  ),
                ],
              ]),
              const SizedBox(height: 3),
              Text(detalle,
                  style: TextStyle(
                      fontSize: 12, height: 1.35, color: cessumMuted(context))),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _selectorFormato() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('¿Cómo la quieres?',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(
          'La versión HTML es la que trae iconos, preguntas que se revelan cuando '
          'tú decides, cronómetro para las actividades y tu guion oculto. Nada de '
          'eso sobrevive a un PDF.',
          style: TextStyle(fontSize: 12.5, height: 1.4, color: cessumMuted(context)),
        ),
        const SizedBox(height: 7),
        Text(
          'La presentación interactiva y el HTML de la tarea son recursos distintos. '
          'Después de generar una tarea puedes revisar su HTML aquí mismo. '
          'Las tareas de productos de una planeación validada se actualizan desde Planeación, no desde esta pantalla.',
          style: TextStyle(fontSize: 12, height: 1.4, color: cessumMuted(context)),
        ),
        const SizedBox(height: 12),
        _opcionFormato('html_pdf', 'HTML + PowerPoint',
            'La interactiva para dar la clase, y la presentación en Google Slides (en tu Drive), PowerPoint y PDF.',
            recomendado: true),
        _opcionFormato('html', 'Solo HTML',
            'Lo más ligero. Se proyecta, se recorre y se coloca en el aula.'),
        _opcionFormato('pdf_docx', 'PowerPoint, Slides y PDF',
            'Sin interactividad. Se arma en Google Slides y de ahí sale el PowerPoint (editable) y el PDF.'),
        const SizedBox(height: 12),
        _selectorCursoDestino(),
        if (_cursoNombreFinal.isNotEmpty) ...[
          Text('Se colocará en: ${_cursoNombreFinal}',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: cessumRed)),
          const SizedBox(height: 10),
        ],
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (_formato != 'pdf_docx')
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: cessumRed, side: const BorderSide(color: cessumRed)),
              onPressed: _htmlCargando ? null : _previsualizarHtml,
              icon: _htmlCargando
                  ? const SizedBox(
                      width: 15, height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2, color: cessumRed))
                  : const Icon(Icons.visibility_outlined, size: 18),
              label: Text(_htmlCargando ? 'Preparando…' : 'Ver la presentación'),
            ),
          if (_formato != 'pdf_docx')
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: (_colocandoHtml || _cursoIdFinal.isEmpty) ? null : _colocarHtmlEnAula,
              icon: _colocandoHtml
                  ? const SizedBox(
                      width: 15, height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.school_outlined, size: 18),
              label: Text(_colocandoHtml ? 'Colocando…' : 'Insertar en el Aula CESSUM'),
            ),
          if (_formato != 'pdf_docx')
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: cessumRed, side: const BorderSide(color: cessumRed)),
              onPressed: (_generandoTarea || _cursoIdFinal.isEmpty) ? null : _generarTarea,
              icon: _generandoTarea
                  ? const SizedBox(
                      width: 15, height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2, color: cessumRed))
                  : const Icon(Icons.assignment_outlined, size: 18),
              label: Text(_generandoTarea ? 'Generando…' : 'Generar tarea de esta sesión'),
            ),
          if (_formato != 'pdf_docx')
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: cessumRed, side: const BorderSide(color: cessumRed)),
              onPressed: _generandoTarea ? null : () => _generarTarea(soloArchivo: true),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: const Text('Solo descargar la tarea (HTML)'),
            ),
          if (_tareaHtmlSesion.isNotEmpty) ...[
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: cessumRed,
                  side: const BorderSide(color: cessumRed)),
              onPressed: () => _abrirHtmlEnPestana(_tareaHtmlSesion),
              icon: const Icon(Icons.preview_outlined, size: 18),
              label: const Text('Revisar HTML de la tarea'),
            ),
            TextButton.icon(
              onPressed: () => _descargarArchivo(
                  'actividad_sesion${_sesion.text.trim()}.html', _tareaHtmlSesion),
              icon: const Icon(Icons.download_done, size: 18),
              label: const Text('Descargar la tarea generada'),
            ),
          ],
          // (7-oct-2026) Cuestionario de repaso y cuadernillo de estudio: de forma ordinaria junto a la tarea.
          if (_formato != 'pdf_docx')
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: cessumGold, side: const BorderSide(color: cessumGold)),
              onPressed: (_generandoCuestionario || _cursoIdFinal.isEmpty) ? null : _generarCuestionario,
              icon: _generandoCuestionario
                  ? const SizedBox(
                      width: 15, height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2, color: cessumGold))
                  : const Icon(Icons.quiz_outlined, size: 18),
              label: Text(_generandoCuestionario ? 'Generando…' : 'Cuestionario de repaso'),
            ),
          if (_formato != 'pdf_docx')
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: cessumGold, side: const BorderSide(color: cessumGold)),
              onPressed: _generandoCuestionario ? null : () => _generarCuestionario(soloArchivo: true),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: const Text('Solo descargar el cuestionario'),
            ),
          if (_cuestionarioHtmlSesion.isNotEmpty)
            TextButton.icon(
              onPressed: () => _descargarArchivo(
                  'cuestionario_sesion${_sesion.text.trim()}.html', _cuestionarioHtmlSesion),
              icon: const Icon(Icons.download_done, size: 18),
              label: const Text('Descargar el cuestionario generado'),
            ),
          if (_formato != 'pdf_docx')
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: cessumGold, side: const BorderSide(color: cessumGold)),
              onPressed: (_generandoCuadernillo || _cursoIdFinal.isEmpty) ? null : _generarCuadernillo,
              icon: _generandoCuadernillo
                  ? const SizedBox(
                      width: 15, height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2, color: cessumGold))
                  : const Icon(Icons.menu_book_outlined, size: 18),
              label: Text(_generandoCuadernillo ? 'Generando…' : 'Cuadernillo de estudio'),
            ),
          if (_formato != 'pdf_docx')
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: cessumGold, side: const BorderSide(color: cessumGold)),
              onPressed: _generandoCuadernillo ? null : () => _generarCuadernillo(soloArchivo: true),
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: const Text('Solo descargar el cuadernillo'),
            ),
          if (_cuadernilloHtmlSesion.isNotEmpty)
            TextButton.icon(
              onPressed: () => _descargarArchivo(
                  'cuadernillo_estudio_sesion${_sesion.text.trim()}.html', _cuadernilloHtmlSesion),
              icon: const Icon(Icons.download_done, size: 18),
              label: const Text('Descargar el cuadernillo generado'),
            ),
          // (8-oct-2026) Actividad semanal en dos pasos: primero una idea corta (editable),
          // y solo al aprobarla se genera el material completo y se coloca en el aula.
          if (_formato != 'pdf_docx')
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: cessumGold, side: const BorderSide(color: cessumGold)),
              onPressed: (_proponiendoActividad || _creandoActividad || _cursoIdFinal.isEmpty) ? null : _actividadSemanal,
              icon: (_proponiendoActividad || _creandoActividad)
                  ? const SizedBox(
                      width: 15, height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2, color: cessumGold))
                  : const Icon(Icons.task_alt_outlined, size: 18),
              label: Text(_proponiendoActividad
                  ? 'Pidiendo la idea…'
                  : (_creandoActividad ? 'Generando…' : 'Actividad de la semana')),
            ),
          if (_actividadHtmlSesion.isNotEmpty)
            TextButton.icon(
              onPressed: () => _descargarArchivo(
                  'actividad_semanal_sesion${_sesion.text.trim()}.html', _actividadHtmlSesion),
              icon: const Icon(Icons.download_done, size: 18),
              label: const Text('Descargar la actividad generada'),
            ),
          // (3-oct-2026) ANTES: solo salía si el formato no era «Solo HTML» y decía «Generar PDF y Word», aunque el Guardián entrega Google
          // Slides, PowerPoint y PDF. Un docente (Cristian Herrera) no encontró cómo bajarla en PowerPoint. Ahora siempre está, y se llama
          // por lo que da.
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumGold, foregroundColor: Colors.white),
            onPressed: _exportando ? null : _exportar,
            icon: _exportando
                ? const SizedBox(
                    width: 15, height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.slideshow, size: 18),
            label: Text(_exportando
                ? 'Armando en Google Slides… (1 a 2 min)'
                : 'Descargar en PowerPoint o Google Slides'),
          ),
        ]),
      ]),
    );
  }

  Future<void> _exportar() async {
    if (_id.isEmpty || _version < 1) return;
    setState(() { _exportando = true; _error = ''; });
    try {
      final j = await _post({'accion': 'diapo_exportar', 'id': _id, 'version': '$_version'}, segundos: 180);
      if (!mounted) return;
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo exportar.');
      setState(() {
        _exportando = false;
        _exportado = {
          'slides': '${j['slidesUrl'] ?? ''}',
          'pdf': '${j['pdfUrl'] ?? ''}',
          'pptx': '${j['pptxUrl'] ?? ''}',
        };
        _fuentesPdf = (j['fuentesPdf'] is List) ? (j['fuentesPdf'] as List).map((e) => '$e').toList() : <String>[];
        _avisosExport = (j['avisos'] is List) ? (j['avisos'] as List).map((e) => '$e').where((e) => e.isNotEmpty).toList() : <String>[];
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${j['nota'] ?? 'Exportado.'}')));
    } catch (e) {
      if (!mounted) return;
      setState(() { _exportando = false; _error = '$e'.replaceFirst('Exception: ', ''); });
    }
  }

  /* (9-sep) COLOCAR EN EL AULA.
     Cierra el ciclo sin salir de la app: el Guardián exporta si hace falta
     y deja la presentación en Moodle, en la semana que le corresponde a esa
     sesión. Colocarla dos veces actualiza la misma, no la duplica. */
  bool _colocando = false;
  Map<String, dynamic> _colocado = {};

  Future<void> _colocarEnAula() async {
    if (_id.isEmpty || _version < 1) return;
    setState(() { _colocando = true; _error = ''; });
    try {
      final cuerpoCA = <String, dynamic>{'accion': 'diapo_colocar_aula', 'id': _id, 'version': '$_version'};
      if (_cursoIdFinal.isNotEmpty) cuerpoCA['courseId'] = _cursoIdFinal;
      final j = await _post(cuerpoCA, segundos: 240);
      if (!mounted) return;
      if (j['sinAula'] == true) {
        setState(() => _colocando = false);
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Esta materia no tiene aula'),
            content: Text('${j['error'] ?? ''}', style: const TextStyle(height: 1.4)),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido'))],
          ),
        );
        return;
      }
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo colocar.');
      setState(() {
        _colocando = false;
        _colocado = Map<String, dynamic>.from(j);
        // Si exportó de paso, se recogen los enlaces para la tarjeta.
        if (_exportado.isEmpty && '${j['aulaUrl'] ?? ''}'.isNotEmpty) {
          _exportado = {'slides': '', 'pdf': '', 'pptx': ''};
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${j['nota'] ?? 'Colocada.'}')));
    } catch (e) {
      if (!mounted) return;
      setState(() { _colocando = false; _error = '$e'.replaceFirst('Exception: ', ''); });
    }
  }

  Widget _tarjetaColocado() {
    if (_colocado.isEmpty) return const SizedBox.shrink();
    final aula = '${_colocado['aulaUrl'] ?? ''}';
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE9F5EC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF9DCFA9)),
      ),
      child: Row(children: [
        const Icon(Icons.check_circle, color: Color(0xFF1E8E3E)),
        const SizedBox(width: 10),
        Expanded(child: Text(
          'En el aula, semana ${_colocado['semana']} · sesión ${_colocado['sesion']}'
          '${'${_colocado['tipo'] ?? ''}'.isNotEmpty ? ' (${_colocado['tipo']})' : ''}.',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
        if (aula.isNotEmpty)
          TextButton(onPressed: () => _abrir(aula), child: const Text('Ver aula')),
        // (3-oct-2026) Paso 6: colocación reversible. Quita del aula lo que puso el generador (por marca); lo del docente no se toca.
        PopupMenuButton<String>(
          tooltip: 'Retirar del aula',
          icon: const Icon(Icons.remove_circle_outline, color: Color(0xFF1E8E3E)),
          onSelected: (que) => _retirarDelAula(que),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'presentacion', child: Text('Retirar la presentación')),
            PopupMenuItem(value: 'interactiva', child: Text('Retirar la interactiva')),
            PopupMenuItem(value: 'tarea', child: Text('Retirar la tarea')),
            PopupMenuItem(value: 'actividad', child: Text('Retirar la actividad de la semana')),
            PopupMenuItem(value: 'todo', child: Text('Retirar todo lo de esta sesión')),
          ]),
      ]),
    );
  }

  Future<void> _retirarDelAula(String que) async {
    if (_id.isEmpty) return;
    final etiqueta = {'presentacion': 'la presentación', 'interactiva': 'la interactiva', 'tarea': 'la tarea', 'actividad': 'la actividad de la semana', 'todo': 'todo lo de esta sesión'}[que] ?? que;
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Retirar del aula'),
      content: Text('Se quitará $etiqueta del aula en Moodle. Solo se retira lo que colocó el generador; lo que tú pusiste a mano no se toca. ¿Continuar?', style: const TextStyle(height: 1.4)),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white), onPressed: () => Navigator.pop(context, true), child: const Text('Retirar'))]));
    if (ok != true) return;
    try {
      final j = await _post({'accion': 'diapo_retirar_aula', 'id': _id, 'que': que, 'confirmar': '1'}, segundos: 120);
      if (!mounted) return;
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo retirar.');
      setState(() { if (que == 'todo' || que == 'presentacion') _colocado = {}; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${j['nota'] ?? 'Retirado.'}'), duration: const Duration(seconds: 6)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))));
    }
  }

  void _abrir(String url) {
    if (url.isEmpty) return;
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
  }

  /* (3-oct-2026) GUARDAR EN MI DRIVE y DESCARGAR DIRECTO.
     El Guardián crea la presentación en Google Slides dentro del Drive INSTITUCIONAL (carpeta «Presentaciones CESSUM») y la comparte con el
     dominio; la tarjeta decía «quedó en tu Drive», y no era cierto. Ahora:
       · «Guardar en mi Drive» abre la página de Google «Hacer una copia» del mismo archivo: la copia queda en el Drive DEL DOCENTE, editable.
       · «Descargar PowerPoint» y «Descargar PDF» usan la exportación directa de Google Slides (baja el archivo, no abre un visor).
     Todo sale del identificador del Slides; si no se puede leer, se usan los enlaces de Drive de siempre. */
  String _idSlides(String url) {
    final m = RegExp(r'/presentation/d/([A-Za-z0-9_-]+)').firstMatch(url);
    return m == null ? '' : (m.group(1) ?? '');
  }

  Widget _tarjetaExportacion() {
    final slides = _exportado['slides'] ?? '';
    final id = _idSlides(slides);
    final base = 'https://docs.google.com/presentation/d/$id';
    final copia = id.isEmpty ? '' : '$base/copy';
    final pptx = id.isEmpty ? (_exportado['pptx'] ?? '') : '$base/export/pptx';
    final pdf = id.isEmpty ? (_exportado['pdf'] ?? '') : '$base/export/pdf';
    if (slides.isEmpty && pptx.isEmpty && pdf.isEmpty) return const SizedBox.shrink();

    Widget boton(String etiqueta, IconData icono, String url, {bool principal = false}) {
      if (url.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 8),
        child: principal
            ? ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
                onPressed: () => _abrir(url),
                icon: Icon(icono, size: 18),
                label: Text(etiqueta),
              )
            : OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: cessumRed, side: const BorderSide(color: cessumRed)),
                onPressed: () => _abrir(url),
                icon: Icon(icono, size: 18),
                label: Text(etiqueta),
              ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F1E8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7C98A)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Tu presentación está lista',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
            'Se creó en Google Slides con la identidad CESSUM. Úsala con tu cuenta @cessum.mx. '
            '«Guardar en mi Drive» te deja una copia tuya y editable en tu propio Drive: en la ventana '
            'que se abre, toca «Hacer una copia». El original queda en la carpeta «Presentaciones CESSUM» del Drive institucional.',
            style: TextStyle(fontSize: 12, height: 1.4, color: cessumMuted(context))),
        const SizedBox(height: 10),
        if (_fuentesPdf.isNotEmpty || _avisosExport.isNotEmpty) ...[
          Row(children: [
            Icon(_fuentesPdf.any((f) => f.toLowerCase().contains('montserrat')) ? Icons.check_circle_outline : Icons.info_outline, size: 15,
                color: _fuentesPdf.any((f) => f.toLowerCase().contains('montserrat')) ? const Color(0xFF2E7D32) : const Color(0xFF9A5B00)),
            const SizedBox(width: 6),
            Expanded(child: Text(
                _fuentesPdf.any((f) => f.toLowerCase().contains('montserrat'))
                    ? 'El PDF salió con Montserrat incrustada.'
                    : (_fuentesPdf.isEmpty ? 'No pude leer qué fuente lleva el PDF.' : 'El PDF salió con otra fuente (${_fuentesPdf.take(3).join(', ')}), no con Montserrat.'),
                style: TextStyle(fontSize: 12, color: cessumMuted(context)))),
          ]),
          ..._avisosExport.map((a) => Padding(padding: const EdgeInsets.only(top: 4), child: Text('· $a', style: TextStyle(fontSize: 12, color: cessumMuted(context))))),
          const SizedBox(height: 8),
        ],
        Wrap(children: [
          boton('Guardar en mi Drive (Google Slides)', Icons.add_to_drive, copia, principal: true),
          boton('Descargar PowerPoint (.pptx)', Icons.slideshow, pptx),
          boton('Descargar PDF', Icons.picture_as_pdf, pdf),
          boton('Ver en Slides', Icons.edit_note, slides),
        ]),
      ]),
    );
  }

  // ─────────────────────────────────────────── UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear presentación'), backgroundColor: cessumRed, foregroundColor: Colors.white, actions: [
        // (5-oct-2026) Presentaciones de otros docentes para copiar y adaptar.
        IconButton(
          tooltip: 'Biblioteca de bloques',
          icon: const Icon(Icons.local_library_outlined),
          onPressed: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => BibliotecaScreen(
                tipoInicial: 'presentacion', destinoMateria: _grupo == null ? null : '${_grupo!['materia']}')));
            if (mounted) _cargar();
          },
        ),
      ]),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              _cabecera(),
              const SizedBox(height: 12),
              if (_error.isNotEmpty) _aviso(_error, error: true),
              if (_paso == 0) _pasoMateria(),
              if (_paso == 1) _pasoMaterial(),
              if (_paso == 2) _pasoControles(),
              if (_paso == 3) _pasoModo(),
              if (_paso == 4) _pasoPreguntas(),
              if (_paso == 5) _pasoEsqueleto(),
              if (_paso == 6) _pasoVersion(),
              if (_paso == 7) _pasoPaquete(),
            ]),
    );
  }

  Widget _cabecera() {
    const nombres = ['Materia', 'Material', 'Cómo la quieres', 'Ruta', 'Preguntas', 'Índice', 'Presentación'];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        for (int i = 0; i < nombres.length; i++) ...[
          if (i == 4 && _modo != 'colaborativo') const SizedBox.shrink() else
          Expanded(child: Container(height: 4, decoration: BoxDecoration(
            color: i <= _paso ? cessumRed : Colors.black12, borderRadius: BorderRadius.circular(2)))),
          if (i < nombres.length - 1) const SizedBox(width: 3),
        ],
      ]),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(child: Text(nombres[_paso], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
        Text('$_usoMes de $_tope generaciones este mes', style: TextStyle(fontSize: 11.5, color: _usoMes >= _tope ? cessumRed : cessumMuted(context))),
      ]),
      if (_grupo != null) Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [
        Expanded(child: Text(
          '${_grupo!['materia']} · ${_grupo!['generacion']} · Grupo ${_grupo!['grupo']}',
          style: TextStyle(fontSize: 12, color: cessumMuted(context)))),
        // (3-oct-2026) Paso 1 del generador: ver el aula antes de generar o colocar. Lo que el docente puso a mano queda protegido.
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: cessumRed, visualDensity: VisualDensity.compact),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AulaRadiografiaScreen(
            programa: '${_grupo!['programa'] ?? ''}', generacion: '${_grupo!['generacion'] ?? ''}', grupo: '${_grupo!['grupo'] ?? ''}', materia: '${_grupo!['materia'] ?? ''}'))),
          icon: const Icon(Icons.fact_check_outlined, size: 16), label: const Text('Ver el aula')),
      ])),
    ]);
  }

  Widget _aviso(String t, {bool error = false, bool ok = false}) => Container(
    margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: error ? const Color(0xFFFDEEF0) : ok ? const Color(0xFFF2F9F3) : const Color(0xFFFBF1DC),
      border: Border.all(color: error ? const Color(0xFFE9B7BC) : ok ? const Color(0xFFC7E4CE) : const Color(0xFFE7C98A)),
      borderRadius: BorderRadius.circular(9)),
    child: Text(t, style: TextStyle(fontSize: 13.5, color: error ? const Color(0xFF8E141D) : ok ? const Color(0xFF1E7A38) : const Color(0xFF6B5A2A))));

  Widget _boton(String t, VoidCallback? f, {bool sec = false}) => sec
      ? OutlinedButton(onPressed: _ocupado ? null : f, style: OutlinedButton.styleFrom(foregroundColor: cessumRed, side: BorderSide(color: cessumRed), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14)), child: Text(t))
      : ElevatedButton(onPressed: _ocupado ? null : f, style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14)),
          child: _ocupado ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(t, style: const TextStyle(fontWeight: FontWeight.w700)));

  // Paso 0 · materia
  // Las presentaciones que ya hizo, para volver a ellas en vez de rehacerlas.
  // (15-sep) USARLA EN OTRO GRUPO. No se duplica: es la misma presentación y
  // se le cambia el grupo. Lo que ya se colocó en un aula no se mueve —ahí
  // quedó como archivo—, así que el grupo anterior conserva el suyo. Cada
  // cambio queda anotado en el historial.
  Future<void> _reasignar() async {
    final gen = TextEditingController(
        text: '${_grupo?['generacion'] ?? ''}');
    final gru = TextEditingController(text: '${_grupo?['grupo'] ?? ''}');
    final ses = TextEditingController(text: _sesion.text);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Usar en otro grupo', style: TextStyle(fontSize: 17)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                  'Es la misma presentación: cambia a qué grupo pertenece. Lo que '
                  'ya colocaste en un aula se queda ahí, no se mueve.',
                  style: TextStyle(fontSize: 12.5, color: Colors.black54)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: gen,
              decoration: const InputDecoration(
                  labelText: 'Generación', border: OutlineInputBorder(),
                  isDense: true, hintText: 'Ej. 26-1'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: gru,
              decoration: const InputDecoration(
                  labelText: 'Grupo', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ses,
              decoration: const InputDecoration(
                  labelText: 'Sesión', border: OutlineInputBorder(), isDense: true),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Actualizar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() { _ocupado = true; _error = ''; });
    try {
      final j = await _post({
        'accion': 'diapo_reasignar',
        'id': _id,
        'generacion': gen.text.trim(),
        'grupo': gru.text.trim(),
        'sesion': ses.text.trim(),
      }, segundos: 45);
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo actualizar.');
      if (!mounted) return;
      setState(() => _ocupado = false);
      await _abrirProyecto(_id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${j['nota'] ?? 'Actualizada.'}'),
            backgroundColor: const Color(0xFF1E8E3E)));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ocupado = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  // Materias distintas entre las presentaciones hechas, para los chips.
  List<String> get _materiasDeCreadas {
    final set = <String>{};
    for (final p in _proyectos) {
      final m = '${p['materia'] ?? ''}'.trim();
      if (m.isNotEmpty) set.add(m);
    }
    final l = set.toList()..sort();
    return l;
  }

  Widget _creadas() {
    if (_proyectos.isEmpty) return const SizedBox.shrink();
    final q = _filtroCreadas.text.trim().toLowerCase();
    final lista = _proyectos.where((p) {
      if (_filtroMateria.isNotEmpty &&
          '${p['materia'] ?? ''}'.trim() != _filtroMateria) {
        return false;
      }
      if (q.isEmpty) return true;
      final heno = '${p['materia'] ?? ''} ${p['grupo'] ?? ''} '
              '${p['programa'] ?? ''} ${p['generacion'] ?? ''} '
              'sesión ${p['sesion'] ?? ''} ${p['sesion'] ?? ''}'
          .toLowerCase();
      // Todas las palabras que escribió deben aparecer: así «meto 3» encuentra
      // la sesión 3 de Metodología sin depender del orden.
      return q.split(RegExp(r'\s+')).every((w) => heno.contains(w));
    }).toList()
      ..sort((a, b) => '${b['actualizado'] ?? b['creado'] ?? ''}'
          .compareTo('${a['actualizado'] ?? a['creado'] ?? ''}'));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(
        onTap: () => setState(() => _verCreadas = !_verCreadas),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Icon(_verCreadas ? Icons.expand_less : Icons.expand_more,
                size: 20, color: cessumRed),
            const SizedBox(width: 6),
            Text('Tus presentaciones (${_proyectos.length})',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: cessumRed)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  _verCreadas ? '' : 'Ábrelas para hacer otra versión sin empezar de cero.',
                  style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
        ),
      ),
      if (_verCreadas) ...[
        TextField(
          controller: _filtroCreadas,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search, size: 19),
            suffixIcon: _filtroCreadas.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _filtroCreadas.clear()),
                  ),
            hintText: 'Buscar por materia, grupo o sesión',
            hintStyle: const TextStyle(fontSize: 13.5),
            border: const OutlineInputBorder(),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          style: const TextStyle(fontSize: 14),
        ),
        if (_materiasDeCreadas.length > 1) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            ChoiceChip(
              label: const Text('Todas', style: TextStyle(fontSize: 12)),
              selected: _filtroMateria.isEmpty,
              selectedColor: cessumGold.withValues(alpha: 0.22),
              onSelected: (_) => setState(() => _filtroMateria = ''),
            ),
            ..._materiasDeCreadas.map((m) => ChoiceChip(
                  label: Text(m.length > 26 ? '${m.substring(0, 24)}…' : m,
                      style: const TextStyle(fontSize: 12)),
                  selected: _filtroMateria == m,
                  selectedColor: cessumGold.withValues(alpha: 0.22),
                  onSelected: (_) => setState(
                      () => _filtroMateria = _filtroMateria == m ? '' : m),
                )),
          ]),
        ],
        const SizedBox(height: 10),
        if (lista.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text('Ninguna presentación coincide con esa búsqueda.',
                style: TextStyle(fontSize: 13, color: cessumMuted(context))),
          ),
        ...lista.map((p) {
          final v = int.tryParse('${p['versiones'] ?? 0}') ?? 0;
          final ses = '${p['sesion'] ?? ''}';
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text('${p['materia'] ?? ''}'
                  '${ses.isNotEmpty && ses != '0' ? ' · Sesión $ses' : ''}',
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
              subtitle: Text(
                  // (15-sep) La generación faltaba y con cinco «Sesión 1»
                  // iguales no había forma de distinguirlas. Va también la
                  // fecha, que es lo que separa dos del mismo grupo.
                  '${p['generacion'] ?? ''}'
                  '${'${p['generacion'] ?? ''}'.isNotEmpty ? ' · ' : ''}'
                  '${p['grupo'] ?? ''}'
                  '${v > 0 ? ' · $v ${v == 1 ? 'versión' : 'versiones'} de 3' : ' · sin versión todavía'}'
                  '${'${p['actualizado'] ?? ''}'.isNotEmpty ? ' · ${p['actualizado']}' : ''}',
                  style: const TextStyle(fontSize: 12.5)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (v >= 3)
                  Text('tope',
                      style: TextStyle(fontSize: 11.5, color: cessumMuted(context)))
                else
                  const Icon(Icons.chevron_right, color: cessumRed),
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      size: 19, color: cessumMuted(context)),
                  tooltip: 'Borrar esta presentación',
                  onPressed: _ocupado
                      ? null
                      : () => _borrarProyecto('${p['id'] ?? ''}',
                          '${p['materia'] ?? 'esta presentación'}'),
                ),
              ]),
              onTap: _ocupado ? null : () => _abrirProyecto('${p['id'] ?? ''}'),
            ),
          );
        }),
      ],
      const SizedBox(height: 10),
      // Banco: las de todos los docentes.
      InkWell(
        onTap: () {
          setState(() => _verBanco = !_verBanco);
          if (_verBanco) _cargarBanco();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Icon(_verBanco ? Icons.expand_less : Icons.expand_more,
                size: 20, color: cessumGold),
            const SizedBox(width: 6),
            const Text('Banco de presentaciones',
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: cessumGold)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  _verBanco ? '' : 'Las de todos los docentes. Tómalas en vez de empezar de cero.',
                  style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
        ),
      ),
      if (_verBanco) ...[
        if (_cargandoBanco)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
                child: SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          )
        else if (_banco.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text('Todavía no hay presentaciones de otros docentes.',
                style: TextStyle(fontSize: 13, color: cessumMuted(context))),
          )
        else
          ..._bancoFiltrado.map((b) {
            final v = int.tryParse('${b['versiones'] ?? 0}') ?? 0;
            final ses = '${b['sesion'] ?? ''}';
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              color: cessumGold.withValues(alpha: 0.05),
              child: ListTile(
                title: Text(
                    '${b['materia'] ?? ''}'
                    '${ses.isNotEmpty && ses != '0' ? ' · Sesión $ses' : ''}',
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w600)),
                subtitle: Text(
                    '${b['generacion'] ?? ''} · ${b['grupo'] ?? ''}'
                    '${v > 0 ? ' · $v ${v == 1 ? 'versión' : 'versiones'}' : ''}'
                    '\nPor ${b['docente'] ?? 'otro docente'}'
                    '${'${b['actualizado'] ?? ''}'.isNotEmpty ? ' · ${b['actualizado']}' : ''}',
                    style: const TextStyle(fontSize: 12.5)),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right, color: cessumGold),
                onTap: _ocupado ? null : () => _abrirProyecto('${b['id'] ?? ''}'),
              ),
            );
          }),
        const SizedBox(height: 6),
      ],
      Divider(color: cessumMuted(context).withValues(alpha: 0.25)),
      const SizedBox(height: 6),
    ]);
  }

  /* (5-oct-2026) ¿La materia está en curso, por empezar o terminada? El servidor ya manda «terminada» (por su fecha de
     término) y la fecha de inicio; aquí solo se clasifica. Si la fecha de inicio no se puede leer, cuenta como en curso. */
  DateTime? _fechaDe(dynamic v) {
    final s = '${v ?? ''}'.trim();
    if (s.isEmpty) return null;
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso;
    final m = RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})').firstMatch(s);
    if (m == null) return null;
    var a = int.parse(m.group(3)!);
    if (a < 100) a += 2000;
    return DateTime(a, int.parse(m.group(2)!), int.parse(m.group(1)!));
  }

  String _vigenciaDe(Map<String, dynamic> g) {
    if (g['terminada'] == true) return 'terminadas';
    final ini = _fechaDe(g['inicio']);
    if (ini != null && ini.isAfter(DateTime.now())) return 'proximas';
    return 'curso';
  }

  int _cuentaVigencia(String v) => v == 'todas' ? _grupos.length : _grupos.where((g) => _vigenciaDe(g) == v).length;

  // Programas distintos en la carga del docente, para los chips.
  List<String> get _programasDeGrupos {
    final set = <String>{};
    for (final g in _grupos) {
      final p = '${g['programa'] ?? ''}'.trim();
      if (p.isNotEmpty) set.add(p);
    }
    final l = set.toList()..sort();
    return l;
  }

  // Materias que quedan tras el buscador y el chip de programa.
  List<Map<String, dynamic>> get _gruposFiltrados {
    final q = _filtroMaterias.text.trim().toLowerCase();
    return _grupos.where((g) {
      if (_filtroVigencia != 'todas' && _vigenciaDe(g) != _filtroVigencia) return false;
      if (_filtroPrograma.isNotEmpty &&
          '${g['programa'] ?? ''}'.trim() != _filtroPrograma) {
        return false;
      }
      if (q.isEmpty) return true;
      final heno = '${g['materia'] ?? ''} ${g['programa'] ?? ''} '
              '${g['generacion'] ?? ''} ${g['grupo'] ?? ''}'
          .toLowerCase();
      return q.split(RegExp(r'\s+')).every((w) => heno.contains(w));
    }).toList();
  }

  // El banco respeta el mismo buscador y los mismos chips de arriba.
  List<Map<String, dynamic>> get _bancoFiltrado {
    final q = _filtroCreadas.text.trim().toLowerCase();
    return _banco.where((b) {
      if (_filtroMateria.isNotEmpty &&
          '${b['materia'] ?? ''}'.trim() != _filtroMateria) {
        return false;
      }
      if (q.isEmpty) return true;
      final heno = '${b['materia'] ?? ''} ${b['grupo'] ?? ''} '
              '${b['programa'] ?? ''} ${b['generacion'] ?? ''} '
              '${b['docente'] ?? ''} sesión ${b['sesion'] ?? ''}'
          .toLowerCase();
      return q.split(RegExp(r'\s+')).every((w) => heno.contains(w));
    }).toList();
  }

  Widget _pasoMateria() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _creadas(),
    const Text('¿Para qué materia?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
    const SizedBox(height: 6),
    Text('Todo lo institucional se llena solo: nombre, programa, grupo, docente.', style: TextStyle(fontSize: 13, color: cessumMuted(context))),
    const SizedBox(height: 14),
    if (_grupos.isEmpty) _aviso('No tienes materias vigentes asignadas. La presentación se liga a una materia; pide a Vicerrectoría que revise tu carga.'),
    // (5-oct-2026) Primero, las materias EN CURSO; las demás, a un toque.
    if (_grupos.isNotEmpty) ...[
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final v in const [('curso', 'En curso'), ('proximas', 'Por empezar'), ('terminadas', 'Terminadas'), ('todas', 'Todas')])
          if (v.$1 == 'todas' || v.$1 == 'curso' || _cuentaVigencia(v.$1) > 0)
            ChoiceChip(
              label: Text('${v.$2} · ${_cuentaVigencia(v.$1)}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              selected: _filtroVigencia == v.$1,
              selectedColor: cessumRed.withValues(alpha: 0.14),
              onSelected: (_) => setState(() => _filtroVigencia = v.$1),
            ),
      ]),
      const SizedBox(height: 10),
      if (_filtroVigencia == 'curso' && _cuentaVigencia('curso') == 0)
        _aviso('No tienes materias en curso en este momento. Revisa «Por empezar» o «Terminadas».'),
    ],
    if (_grupos.length > 4) ...[
      TextField(
        controller: _filtroMaterias,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 19),
          suffixIcon: _filtroMaterias.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _filtroMaterias.clear()),
                ),
          hintText: 'Buscar materia, programa, generación o grupo',
          hintStyle: const TextStyle(fontSize: 13.5),
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        style: const TextStyle(fontSize: 14),
      ),
      if (_programasDeGrupos.length > 1) ...[
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          ChoiceChip(
            label: const Text('Todos', style: TextStyle(fontSize: 12)),
            selected: _filtroPrograma.isEmpty,
            selectedColor: cessumGold.withValues(alpha: 0.22),
            onSelected: (_) => setState(() => _filtroPrograma = ''),
          ),
          ..._programasDeGrupos.map((pr) => ChoiceChip(
                label: Text(pr.length > 28 ? '${pr.substring(0, 26)}…' : pr,
                    style: const TextStyle(fontSize: 12)),
                selected: _filtroPrograma == pr,
                selectedColor: cessumGold.withValues(alpha: 0.22),
                onSelected: (_) => setState(
                    () => _filtroPrograma = _filtroPrograma == pr ? '' : pr),
              )),
        ]),
      ],
      const SizedBox(height: 12),
      if (_gruposFiltrados.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text('Ninguna materia coincide con esa búsqueda.',
              style: TextStyle(fontSize: 13, color: cessumMuted(context))),
        ),
    ],
    ..._gruposFiltrados.map((g) => Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(
      title: Text('${g['materia']}', style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${g['programa']} · ${g['generacion']} · Grupo ${g['grupo']}'),
        if (_avanceDe(g).isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(_avanceDe(g),
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: cessumGold)),
        ],
      ]),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        setState(() {
          _grupo = g; _paso = 1;
          // Materia nueva: se olvida lo que se hubiera elegido para la anterior.
          _cursoModo = 'sugerido'; _cursoMateriaMia = null;
          _cursoCandidatos = []; _cursoCandidatoElegido = 0; _cursoResolverError = '';
          _courseIdManual.clear();
        });
        _buscarPlaneaciones();
        _resolverCurso(g);
      },
    ))),
  ]);

  /* Busca si la materia elegida tiene una planeación VALIDADA. El backend ya
     exige la validación en planea_material_sesion, así que aquí solo se
     muestra lo que de verdad se puede usar. */
  Future<void> _buscarPlaneaciones() async {
    if (_grupo == null) return;
    setState(() { _planCargando = true; _planValidadas = []; _planNota = ''; });
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=planea_mis_entregas'
              '&correo=${Uri.encodeComponent(_correo)}'
              '&actor=${Uri.encodeComponent(_correo)}'))
          .timeout(const Duration(seconds: 45));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      final mat = '${_grupo?['materia'] ?? ''}'.toLowerCase().trim();
      final lista = ((data['entregas'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) =>
              '${e['estado'] ?? ''}'.toLowerCase().contains('valid') &&
              '${e['materia'] ?? ''}'.toLowerCase().trim() == mat)
          .toList();
      setState(() {
        _planValidadas = lista;
        _planCargando = false;
        _planNota = lista.isEmpty
            ? 'No hay una planeación validada de esta materia. Puedes subir tu '
              'material o generarla primero desde «Planeación didáctica».'
            : '';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() { _planCargando = false; _planNota = ''; });
    }
  }

  /* Trae el contenido de UNA sesión: una planeación de siete no cabe en una
     presentación, y mezclarlas daría un material sin hilo. */
  Future<void> _usarPlaneacion(Map<String, dynamic> e) async {
    // (8-oct-2026) Antes `ctrl` se creaba DENTRO del builder y nunca se destruía: una fuga de
    // controlador cada vez que se abría este diálogo. Ahora se crea aquí fuera, para poder
    // destruirlo en cuanto el diálogo se cierra, por cualquier camino.
    final ctrl = TextEditingController(text: '1');
    final n = await showDialog<int>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('¿De qué sesión?'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
              'La presentación se arma con el contenido de una sesión. '
              'Escribe cuál vas a impartir.',
              style: TextStyle(fontSize: 12.5, color: cessumMuted(context)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'Número de sesión', border: OutlineInputBorder()),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () =>
                  Navigator.pop(ctx, int.tryParse(ctrl.text.trim()) ?? 1),
              child: const Text('Usar'),
            ),
          ],
        );
      },
    );
    ctrl.dispose();
    if (n == null) return;

    // (8-oct-2026) Antes no se arrancaba el reloj aquí (a diferencia de todos los demás flujos
    // que usan `_ocupado`), así que la barra de espera mostraba un tiempo congelado o de una
    // operación anterior mientras esta llamada seguía trabajando.
    setState(() => _ocupado = true); _arrancarReloj();
    try {
      final j = await _post({
        'accion': 'planea_material_sesion',
        'id': '${e['idPlaneacion'] ?? ''}',
        'sesion': '$n',
      }, segundos: 120);
      if (!mounted) return;
      final texto = '${j['material'] ?? ''}';
      if (texto.trim().isEmpty) throw Exception('La sesión no trae contenido.');
      setState(() {
        // Se AÑADE, no se pisa: puede que ya haya pegado algo suyo.
        _material.text = _material.text.trim().isEmpty
            ? texto
            : '${_material.text}\n\n--- Planeación · sesión $n ---\n$texto';
        _sesion.text = '$n';
        _pararReloj(); _ocupado = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Material de la sesión $n cargado desde tu planeación.'),
      ));
    } catch (err) {
      if (!mounted) return;
      setState(() { _pararReloj(); _ocupado = false; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${err}'.replaceFirst('Exception: ', '')),
      ));
    }
  }

  Widget _tarjetaPlaneacion() {
    if (_planCargando) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          const SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Text('Buscando tu planeación validada…',
              style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
        ]),
      );
    }
    if (_planValidadas.isEmpty) {
      if (_planNota.isEmpty) return const SizedBox.shrink();
      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: const Color(0xFFFBF7EF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cessumGold.withValues(alpha: 0.4)),
        ),
        child: Text(_planNota,
            style: TextStyle(
                fontSize: 11.5, height: 1.4, color: cessumMuted(context))),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ..._planValidadas.map((e) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: cessumRed.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cessumRed.withValues(alpha: 0.3)),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _ocupado ? null : () => _usarPlaneacion(e),
                child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: Row(children: [
                    Icon(Icons.auto_stories, color: cessumRed, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Usar tu planeación validada',
                              style: TextStyle(
                                  fontSize: 14.5, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 3),
                          Text(
                            '${e['materia']} · validada el '
                            '${e['dictaminada'] ?? e['entregada'] ?? ''}. '
                            'Elige la sesión y el material se carga solo.',
                            style: TextStyle(
                                fontSize: 12,
                                height: 1.35,
                                color: cessumMuted(context)),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: cessumRed),
                  ]),
                ),
              ),
            ),
            ),
            _botonPaquete(e),
          ])),
    ]);
  }

  // Paso 1 · material
  Widget _pasoMaterial() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _barraTrabajando('Trabajando con tu material…'),
    const Text('Tu material', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
    const SizedBox(height: 6),
    Text('Sube lo que ya tienes o pega el texto. Con más material, mejor presentación.', style: TextStyle(fontSize: 13, color: cessumMuted(context))),
    const SizedBox(height: 14),
    _tarjetaPlaneacion(),
    Row(children: [
      _boton('Subir archivos (Word, texto, PDF, imágenes)', _subirArchivo, sec: true),
    ]),
    if (_archivosLeidos.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Wrap(spacing: 6, children: _archivosLeidos.map((a) => Chip(label: Text(a, style: const TextStyle(fontSize: 11)))).toList())),
    const SizedBox(height: 12),
    TextField(controller: _material, minLines: 8, maxLines: 20, onChanged: (_) => setState(() {}),
      decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Texto del material', hintText: 'Pega aquí tus apuntes, el artículo, el capítulo, lo que vayas a exponer…', alignLabelWithHint: true)),
    const SizedBox(height: 6),
    Text('${_material.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length} palabras · ${_material.text.length} caracteres'
        '${_material.text.length < 200 ? ' · se necesitan al menos 200' : _material.text.length < 1500 ? ' · alcanza para unas 6 diapositivas' : ''}',
      style: TextStyle(fontSize: 12, color: cessumMuted(context))),
    const SizedBox(height: 12),
    TextField(controller: _sesion, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Sesión (opcional)', hintText: 'Sesión 3 · 6 de septiembre')),
    const SizedBox(height: 16),
    Row(children: [
      _boton('Atrás', () => setState(() => _paso = widget.grupoInicial != null ? 1 : 0), sec: true),
      const SizedBox(width: 10),
      _boton('Siguiente', _material.text.trim().length >= 200 ? () => setState(() => _paso = 2) : null),
    ]),
  ]);

  // Paso 2 · controles
  Widget _pasoControles() {
    Widget sel<T>(String label, T valor, Map<T, String> ops, void Function(T) f) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<T>(value: valor, decoration: InputDecoration(border: const OutlineInputBorder(), labelText: label),
        items: ops.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(), onChanged: (v) { if (v != null) setState(() => f(v)); }));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _avisoPaqueteControles(),
      const Text('¿Cómo la quieres?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 14),
      sel<int?>('Cuántas diapositivas', _numDiapos, {null: 'Las que hagan falta', 6: '6', 8: '8', 10: '10', 12: '12', 15: '15', 20: '20'}, (v) => _numDiapos = v),
      sel<String>('Nivel del lenguaje', _lenguaje, {'técnico': 'Técnico · vocabulario disciplinar', 'intermedio': 'Intermedio · técnico con explicación', 'didáctico': 'Didáctico · accesible, con ejemplos'}, (v) => _lenguaje = v),
      sel<String>('Profundidad', _profundidad, {'panorama': 'Panorama · visión general', 'desarrollo': 'Desarrollo · conceptos con ejemplos', 'profundización': 'Profundización · matices y debates'}, (v) => _profundidad = v),
      sel<String>('Tipo de sesión', _tipoSesion, {'exposición': 'Exposición', 'taller': 'Taller', 'seminario': 'Seminario', 'repaso': 'Repaso'}, (v) => _tipoSesion = v),
      sel<int>('Duración', _duracion, {30: '30 minutos', 60: '60 minutos', 90: '90 minutos', 120: '120 minutos'}, (v) => _duracion = v),
      const SizedBox(height: 6),
      const Text('Preguntas para el grupo', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      Text('Van al margen, sutiles, una cada tres o cuatro diapositivas. Las interacciones complejas son las dos sustitutivas (niveles 4 y 5); los tres primeros niveles se resuelven con lo que está en la situación.', style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
      const SizedBox(height: 8),
      ..._nivelesInfo.entries.map((e) => CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero,
        value: _niveles.contains(e.key) && !_sinPreguntas, onChanged: _sinPreguntas ? null : (v) => setState(() => v == true ? _niveles.add(e.key) : _niveles.remove(e.key)),
        title: Text(e.value[0], style: const TextStyle(fontSize: 14)), subtitle: Text('pide al alumno ${e.value[1]}', style: const TextStyle(fontSize: 12)))),
      CheckboxListTile(dense: true, contentPadding: EdgeInsets.zero, value: _sinPreguntas, onChanged: (v) => setState(() => _sinPreguntas = v == true),
        title: const Text('Sin preguntas esta vez', style: TextStyle(fontSize: 14))),

      const SizedBox(height: 14),
      const Text('Gráficos de apoyo', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      Text('Se construyen con datos de tu material: comparativas, líneas de tiempo, procesos. No son imágenes. Editables en PowerPoint.', style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
      const SizedBox(height: 8),
      sel<String>('Cuántos', _graficos, {'ninguno': 'Ninguno', 'pocos': 'Pocos · uno cada 3-4 diapositivas', 'varios': 'Varios · en la mitad de las diapositivas', 'todos': 'Todos los que ayuden', '1': 'Exactamente 1', '2': 'Exactamente 2', '3': 'Exactamente 3', '5': 'Exactamente 5'}, (v) => _graficos = v),
      if (_graficos != 'ninguno') ...[
        Text('Tipos que puede usar (toca para quitar los que no quieras)', style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: _graficosInfo.entries.map((e) => FilterChip(
          label: Text(e.value[0], style: const TextStyle(fontSize: 12.5)), tooltip: e.value[1],
          selected: _tiposGrafico.contains(e.key), selectedColor: cessumRed.withValues(alpha: 0.15), checkmarkColor: cessumRed,
          onSelected: (v) => setState(() => v ? _tiposGrafico.add(e.key) : _tiposGrafico.remove(e.key)))).toList()),
        const SizedBox(height: 12),
      ],

      const Text('Espacios para imágenes', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      Text('La IA no pone imágenes: deja el espacio delimitado con una sugerencia de qué va ahí. Tú la colocas en PowerPoint con clic derecho → Cambiar imagen.', style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
      const SizedBox(height: 8),
      sel<String>('Cuántos espacios', _espaciosImagen, {'ninguno': 'Ninguno', 'algunos': 'Algunos · solo donde una imagen ayude de verdad', 'varios': 'Varios · en la mayoría de las diapositivas'}, (v) => _espaciosImagen = v),

      const SizedBox(height: 14),
      const Text('Plantilla', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      Text('Cinco composiciones. Todas con el logo, Montserrat y los colores de CESSUM: lo que cambia es cómo se acomoda. Toca una para verla.', style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
      const SizedBox(height: 10),
      ..._plantillasInfo.entries.map((e) {
        final sel = _plantilla == e.key;
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: sel ? cessumRed : Colors.black12, width: sel ? 2.5 : 1)),
          child: InkWell(
            onTap: () => setState(() { _plantilla = e.key; _paleta = e.value[2]; }),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // La vista previa real: portada y una diapositiva de contenido,
              // generadas por el mismo código que producirá el PowerPoint.
              AspectRatio(aspectRatio: 720 / 205, child: Image.network(
                'https://app.cessum.mx/plantillas/${e.key}.png', fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: const Color(0xFFF5F1E8), alignment: Alignment.center, child: Text(e.value[0], style: TextStyle(color: cessumMuted(context)))),
              )),
              Padding(padding: const EdgeInsets.fromLTRB(12, 10, 12, 12), child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Text(e.value[0], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)), const SizedBox(width: 8), _muestraPaleta(e.value[2])]),
                  const SizedBox(height: 2),
                  Text(e.value[1], style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
                ])),
                if (sel) Icon(Icons.check_circle, color: cessumRed),
              ])),
            ]),
          ),
        );
      }),
      const SizedBox(height: 6),
      const Text('Paleta', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      Text('Cada plantilla trae la suya, pero puedes cambiarla. Siempre con los colores de CESSUM: lo que cambia es cuál domina.', style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: _paletasInfo.entries.map((e) => ChoiceChip(
        label: Row(mainAxisSize: MainAxisSize.min, children: [_muestraPaleta(e.key), const SizedBox(width: 6), Text(e.value[0], style: const TextStyle(fontSize: 13))]),
        selected: _paleta == e.key, selectedColor: cessumRed.withValues(alpha: 0.15), onSelected: (_) => setState(() => _paleta = e.key))).toList()),
      const SizedBox(height: 14),
      const Text('Íconos', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      Text('Un ícono por diapositiva, elegido por la IA según la idea central, de un catálogo de 58 en los colores de la marca.', style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
      const SizedBox(height: 8),
      sel<String>('Cómo van', _iconos, {'ninguno': 'Sin íconos', 'discretos': 'Discretos · pequeños, junto al título', 'destacados': 'Destacados · grandes, al lado del contenido'}, (v) => _iconos = v),

      const SizedBox(height: 14),
      const Text('Versión interactiva (HTML)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      Text('Además del PowerPoint y el PDF, sale un archivo HTML para proyectar: el mismo contenido, con actividades que el grupo resuelve en pantalla, y el módulo Aula —lista del grupo, ruleta de participaciones y pase de lista— que reporta al Guardián.', style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
      const SizedBox(height: 8),
      sel<String>('Nivel de interactividad', _interactividad, {'ninguna': 'Ninguna · solo proyectar', 'ligera': 'Ligera · piensa y revela, votaciones', 'media': 'Media · una actividad cada 2-3 diapositivas', 'alta': 'Alta · actividad en casi todas'}, (v) => _interactividad = v),
      if (_interactividad != 'ninguna') ...[
        Text('Tipos de actividad (toca para quitar los que no quieras)', style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: _interactivosInfo.entries.map((e) => FilterChip(
          label: Text(e.value[0], style: const TextStyle(fontSize: 12.5)), tooltip: e.value[1],
          selected: _tiposInteractivo.contains(e.key), selectedColor: cessumRed.withValues(alpha: 0.15), checkmarkColor: cessumRed,
          onSelected: (v) => setState(() => v ? _tiposInteractivo.add(e.key) : _tiposInteractivo.remove(e.key)))).toList()),
      ],
      Text('La tipografía es Montserrat, la de CESSUM. Al descargar verás cómo instalarla si tu PowerPoint no la tiene.', style: TextStyle(fontSize: 12, color: cessumMuted(context), fontStyle: FontStyle.italic)),
      const SizedBox(height: 16),
      Row(children: [
        _boton('Atrás', () => setState(() => _paso = 1), sec: true),
        const SizedBox(width: 10),
        _paqueteDe != null
            ? _boton('Generar el paquete completo', _paqueteCompleto)
            : _boton('Siguiente', () => setState(() => _paso = 3)),
      ]),
    ]);
  }

  Widget _muestraPaleta(String k) {
    const m = {
      'clasica': [Color(0xFFB11D29), Color(0xFFB0863A), Color(0xFF211913)],
      'sobria': [Color(0xFF211913), Color(0xFFB11D29), Color(0xFFF5F1E8)],
      'calida': [Color(0xFFF5F1E8), Color(0xFFB0863A), Color(0xFFB11D29)],
      'nocturna': [Color(0xFF211913), Color(0xFFB0863A), Color(0xFFF5F1E8)],
    };
    return Row(mainAxisSize: MainAxisSize.min, children: (m[k] ?? []).map((c) => Container(
      width: 16, height: 16, margin: const EdgeInsets.only(left: 3),
      decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.black12)))).toList());
  }

  // Paso 3 · modo
  Widget _pasoModo() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _barraTrabajando('Preparando las preguntas de tu clase…'),
    const Text('¿Cómo quieres trabajar?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
    const SizedBox(height: 14),
    _tarjetaModo('colaborativo', 'Colaborativa', 'La IA te hace cinco o siete preguntas sobre tu material —qué es el eje, qué debe quedar claro, qué ejemplos usar— y con tus respuestas propone el índice. Más tuya.', Icons.forum_outlined),
    _tarjetaModo('autonomo', 'Autónoma', 'La IA propone el índice bajo su criterio, con tu material y tus controles. Tú lo corriges antes de generar. Más rápida.', Icons.auto_awesome_outlined),
    const SizedBox(height: 8),
    _aviso('En las dos rutas, primero verás el índice y podrás editarlo. Hasta que no lo apruebes, no se generan las diapositivas.'),
    Row(children: [_boton('Atrás', () => setState(() => _paso = 2), sec: true), const SizedBox(width: 10), _boton(_modo == 'colaborativo' ? 'Empezar la conversación' : 'Proponer el índice', _iniciar)]),
  ]);

  Widget _tarjetaModo(String v, String t, String d, IconData ic) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: _modo == v ? cessumRed : Colors.black12, width: _modo == v ? 2 : 1)),
    child: ListTile(leading: Icon(ic, color: cessumRed, size: 28), title: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(d, style: const TextStyle(fontSize: 13)), onTap: () => setState(() => _modo = v),
      trailing: Radio<String>(value: v, groupValue: _modo, onChanged: (x) => setState(() => _modo = x!), activeColor: cessumRed)));

  // Paso 4 · preguntas (colaborativo)
  Widget _pasoPreguntas() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _barraTrabajando('Armando el esqueleto de la presentación…'),
    const Text('Cuéntame cómo la quieres', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
    const SizedBox(height: 6),
    Text('Responde lo que quieras; lo que dejes vacío lo decide la IA. Toca una opción o escribe la tuya.', style: TextStyle(fontSize: 13, color: cessumMuted(context))),
    const SizedBox(height: 14),
    ..._preguntas.map((p) {
      final c = _respuestas['${p['id']}']!;
      final ops = ((p['opciones'] as List?) ?? []).map((e) => '$e').toList();
      return Card(margin: const EdgeInsets.only(bottom: 12), child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${p['texto']}', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
        if (ops.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Wrap(spacing: 6, runSpacing: 6, children: ops.map((o) => ActionChip(label: Text(o, style: const TextStyle(fontSize: 12.5)),
          backgroundColor: c.text == o ? cessumRed.withValues(alpha: 0.12) : null, onPressed: () => setState(() => c.text = o))).toList())),
        const SizedBox(height: 8),
        TextField(controller: c, minLines: 1, maxLines: 3, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Tu respuesta…', isDense: true)),
      ])));
    }),
    Row(children: [_boton('Atrás', () => setState(() => _paso = 3), sec: true), const SizedBox(width: 10), _boton('Proponer el índice', _pedirEsqueleto)]),
  ]);

  // Paso 5 · esqueleto editable
  void _moverDiapo(List<Map<String, dynamic>> ds, int desde, int hasta) {
    if (hasta < 0 || hasta >= ds.length) return;
    setState(() {
      final it = ds.removeAt(desde);
      ds.insert(hasta, it);
      for (int k = 0; k < ds.length; k++) ds[k]['n'] = k + 1;
      _esqueleto!['diapositivas'] = ds;
    });
  }

  /* El «+» entre renglones: inserta EN ESA POSICIÓN, no al final. Discreto a
     propósito —una línea con un botón pequeño— para que la lista siga
     leyéndose como índice y no como barra de herramientas. */
  Widget _masAqui(List<Map<String, dynamic>> ds, int pos, {bool ultimo = false}) {
    return InkWell(
      onTap: () => setState(() {
        ds.insert(pos, {
          'n': pos + 1,
          'titulo': 'Nueva diapositiva',
          'que': 'Escribe de qué va',
          'tipo': 'contenido'
        });
        for (int k = 0; k < ds.length; k++) ds[k]['n'] = k + 1;
        _esqueleto!['diapositivas'] = ds;
      }),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: ultimo ? 10 : 3),
        child: Row(children: [
          Icon(Icons.add_circle_outline, size: ultimo ? 20 : 16, color: cessumRed),
          const SizedBox(width: 8),
          Text(
            ultimo ? 'Agregar diapositiva al final' : 'Insertar aquí',
            style: TextStyle(
                fontSize: ultimo ? 13.5 : 11.5,
                fontWeight: ultimo ? FontWeight.w600 : FontWeight.w500,
                color: cessumRed.withValues(alpha: ultimo ? 1 : 0.75)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
                height: 1, color: cessumRed.withValues(alpha: ultimo ? 0.25 : 0.12)),
          ),
        ]),
      ),
    );
  }

  List<Widget> _listaEsqueleto(List<Map<String, dynamic>> ds) {
    final out = <Widget>[];
    for (int i = 0; i < ds.length; i++) {
      if (i > 0) out.add(_masAqui(ds, i));
      out.add(Card(
        margin: const EdgeInsets.only(bottom: 4),
        child: ListTile(
          leading: CircleAvatar(
            radius: 14,
            backgroundColor: cessumRed,
            child: Text('${i + 1}',
                style: const TextStyle(
                    color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          title: TextFormField(
            initialValue: '${ds[i]['titulo']}',
            onChanged: (v) => ds[i]['titulo'] = v,
            decoration: const InputDecoration(isDense: true, border: InputBorder.none),
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Text(
            '${ds[i]['que']}'
            '${ds[i]['pregunta_nivel'] != null && '${ds[i]['pregunta_nivel']}' != 'null' && '${ds[i]['pregunta_nivel']}'.isNotEmpty ? '  ✦ pregunta ${ds[i]['pregunta_nivel']}' : ''}',
            style: const TextStyle(fontSize: 12),
          ),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              tooltip: 'Subir',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.keyboard_arrow_up, size: 20),
              onPressed: i == 0 ? null : () => _moverDiapo(ds, i, i - 1),
            ),
            IconButton(
              tooltip: 'Bajar',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.keyboard_arrow_down, size: 20),
              onPressed: i == ds.length - 1 ? null : () => _moverDiapo(ds, i, i + 1),
            ),
            IconButton(
              tooltip: 'Quitar',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() {
                ds.removeAt(i);
                for (int k = 0; k < ds.length; k++) ds[k]['n'] = k + 1;
                _esqueleto!['diapositivas'] = ds;
              }),
            ),
          ]),
        ),
      ));
    }
    return out;
  }

  Widget _pasoEsqueleto() {
    final ds = ((_esqueleto?['diapositivas'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('El índice', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text('Reordena, quita, cambia títulos. Hasta que no apruebes esto no se gasta en contenido.', style: TextStyle(fontSize: 13, color: cessumMuted(context))),
      if ('${_esqueleto?['nota'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: _aviso('${_esqueleto!['nota']}')),
      const SizedBox(height: 10),
      TextFormField(initialValue: '${_esqueleto?['titulo'] ?? ''}', onChanged: (v) => _esqueleto!['titulo'] = v,
        decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Título de la presentación'), style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      // (10-sep) SUBIR, BAJAR E INSERTAR ENTRE DIAPOSITIVAS.
      // El arrastre ya existía, pero en pantalla táctil y con listas largas
      // es incómodo y fácil de soltar donde no era. Las flechas mueven de
      // una en una, y el «+» entre renglones deja meter una diapositiva
      // justo donde hace falta en vez de agregarla al final y arrastrarla.
      ..._listaEsqueleto(ds),
      _masAqui(ds, ds.length, ultimo: true),
      const SizedBox(height: 12),
      Row(children: [_boton('Atrás', () => setState(() => _paso = _modo == 'colaborativo' ? 4 : 3), sec: true), const SizedBox(width: 10),
        _boton('Aprobar y generar (${ds.length} diapositivas)', ds.isEmpty ? null : _generar)]),
    ]);
  }

  // Paso 6 · versión lista
  Widget _pasoVersion() {
    final ds = ((_presentacion?['diapositivas'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_paquete.isNotEmpty)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _paso = 7),
            icon: const Icon(Icons.arrow_back, size: 16),
            label: const Text('Volver al paquete completo'),
          ),
        ),
      Row(children: [
        Expanded(child: Text('${_presentacion?['titulo'] ?? 'Presentación'}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: cessumGold.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
          child: Text('Versión $_version de 3', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
      ]),
      const SizedBox(height: 4),
      Text('${ds.length} diapositivas · ${ds.where((d) => '${d['pregunta'] ?? ''}'.isNotEmpty).length} preguntas para el grupo', style: TextStyle(fontSize: 13, color: cessumMuted(context))),
      const SizedBox(height: 10),
      // (8-oct-2026) Revisión lámina por lámina: visto bueno o chat de ajuste por diapositiva, antes de exportar o colocar en el aula.
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: cessumRed, side: const BorderSide(color: cessumRed)),
          onPressed: _id.isEmpty ? null : () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => DiapoRevisionScreen(
                id: _id,
                tituloProyecto: '${_presentacion?['titulo'] ?? 'Presentación'}',
              ),
            ));
          },
          icon: const Icon(Icons.fact_check_outlined, size: 18),
          label: const Text('Revisar lámina por lámina'),
        ),
      ),
      const SizedBox(height: 14),
      _avisoVoz(),
      /* (3-oct-2026) Las descargas van ARRIBA, a la vista al abrir: un docente preguntó «¿cómo se descarga en ppt?» con el botón a media página. */
      if (_exportado.values.any((v) => v.isNotEmpty)) _tarjetaExportacion()   // (colocar en el aula deja el mapa con valores vacíos: no cuenta)
      else Padding(padding: const EdgeInsets.only(bottom: 10), child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(backgroundColor: cessumGold, foregroundColor: Colors.white),
        onPressed: _exportando ? null : _exportar,
        icon: _exportando ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.slideshow, size: 18),
        label: Text(_exportando ? 'Armando en Google Slides… (1 a 2 min)' : 'Descargar en PowerPoint o Google Slides'))),
      _aviso('Lista. Toca «Descargar en PowerPoint o Google Slides» para bajarla en PowerPoint (editable) o guardarla en tu Drive; también sale en PDF, en HTML interactivo con el módulo Aula, o el guion del docente en Word.', ok: true),
      _selectorFormato(),
      const SizedBox(height: 8),
      // Solo tiene sentido si la presentación viene de una sesión numerada:
      // sin sesión no hay semana a la cual mandarla.
      if (widget.sesionDePlaneacion > 0)
        Row(children: [_boton(_colocando ? 'Colocando en el aula…' : 'Colocar en el aula (semana de esta sesión)',
            (_colocando || _cursoIdFinal.isEmpty) ? () {} : _colocarEnAula)]),
      const SizedBox(height: 10),
      _tarjetaColocado(),
      const SizedBox(height: 8),
      ...ds.map((d) => Card(margin: const EdgeInsets.only(bottom: 8), child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(radius: 12, backgroundColor: d['tipo'] == 'portada' ? cessumInk(context) : cessumRed, child: Text('${d['n']}', style: const TextStyle(color: Colors.white, fontSize: 11))),
          const SizedBox(width: 8),
          Expanded(child: Text('${d['titulo']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14))),
        ]),
        if (((d['vinetas'] as List?) ?? []).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6, left: 32), child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: (d['vinetas'] as List).map((v) => Text('• $v', style: const TextStyle(fontSize: 13))).toList())),
        if ('${d['actividad'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6, left: 32), child: Text('Actividad: ${d['actividad']}', style: const TextStyle(fontSize: 12.5, color: Color(0xFF1E7A38)))),
        if ('${d['pregunta'] ?? ''}'.isNotEmpty) Container(margin: const EdgeInsets.only(top: 8, left: 32), padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFFFBF1DC), border: const Border(left: BorderSide(color: Color(0xFFB0863A), width: 3))),
          child: Text('✦ ${d['pregunta']}${'${d['pregunta_nivel'] ?? ''}'.isNotEmpty ? '  (${d['pregunta_nivel']})' : ''}', style: const TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic, color: Color(0xFF6B5A2A)))),
      ])))),
      const SizedBox(height: 14),
      if (_quedan > 0) ...[
        const Text('¿Cambios?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        Text('Escribe qué quieres distinto y pide otra versión. Te ${_quedan == 1 ? 'queda 1' : 'quedan $_quedan'}. Las versiones anteriores no se pierden.', style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
        const SizedBox(height: 8),
        TextField(controller: _retro, minLines: 2, maxLines: 5, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Ej.: la diapositiva 5 con más ejemplos de Sonora; menos texto en la 3; agrega una sobre evaluación…')),
        const SizedBox(height: 8),
        if (_historial.isNotEmpty) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: cessumGold.withValues(alpha: 0.08),
              border: Border(left: BorderSide(color: cessumGold, width: 2)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Historial de cambios',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      letterSpacing: 1.1, color: cessumGold)),
              const SizedBox(height: 4),
              Text(_historial,
                  style: const TextStyle(fontSize: 12, height: 1.5)),
            ]),
          ),
        ],
        Row(children: [
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: cessumGold),
            onPressed: _ocupado ? null : _reasignar,
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text('Usar en otro grupo',
                style: TextStyle(fontSize: 12.5)),
          ),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          _boton('Pedir versión ${_version + 1}', _revisar),
          const SizedBox(width: 8),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: cessumMuted(context)),
            onPressed: _ocupado ? null : () => _borrarVersion(_version),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text('Borrar la versión $_version',
                style: const TextStyle(fontSize: 12.5)),
          ),
        ]),
      ] else ...[
        _aviso('Este proyecto ya tiene sus tres versiones, que es el máximo. '
            'Si alguna no sirvió, bórrala y ese lugar queda libre para generar otra.'),
        const SizedBox(height: 8),
        Row(children: [
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: cessumRed),
            onPressed: _ocupado ? null : () => _borrarVersion(_version),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text('Borrar la versión $_version que estoy viendo',
                style: const TextStyle(fontSize: 12.5)),
          ),
        ]),
      ],
      const SizedBox(height: 16),
      _boton('Empezar otra presentación', () { setState(() { _paso = widget.grupoInicial != null ? 1 : 0; _id = ''; _esqueleto = null; _presentacion = null; _version = 0; _quedan = 3; _versionesHechas = 0; _exportado = {}; _colocado = {}; _preguntas = []; _material.clear(); _archivosLeidos.clear(); _error = ''; }); _cargar(); }, sec: true),
    ]);
  }
}
