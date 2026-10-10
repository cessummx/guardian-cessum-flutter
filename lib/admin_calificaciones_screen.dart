import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'planes_estudio.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Pantalla SOLO para administradores: buscar a un alumno por matrícula y ver
/// TODAS las materias de su plan. Las que ya tienen calificación se pueden
/// corregir o borrar; las pendientes (—) se pueden capturar. Todo se guarda en
/// la hoja "Calificaciones" (la base real que ve la app) con estatus "Validada".
class AdminCalificacionesScreen extends StatefulWidget {
  // Si viene una matrícula, la pantalla la pre-carga y busca sola.
  final String? matriculaInicial;
  const AdminCalificacionesScreen({super.key, this.matriculaInicial});

  @override
  State<AdminCalificacionesScreen> createState() =>
      _AdminCalificacionesScreenState();
}

const Color _verdeOk = Color(0xFF1E8E3E);

// Alumno encontrado al buscar por nombre/matrícula (de la base de grupos).
class _Candidato {
  final String matricula;
  final String nombre;
  final String programa;
  const _Candidato(this.matricula, this.nombre, this.programa);
}

// Una calificación tal como vive en la hoja, con su número de fila.
class _CalifAdmin {
  final int fila;
  String programa;
  String generacion;
  String grupo;
  String claveMateria;
  String materia;
  String ciclo;
  String calificacion;
  String enLetra;
  String estatus;
  String docente;
  String recursada;

  _CalifAdmin({
    required this.fila,
    required this.programa,
    required this.generacion,
    required this.grupo,
    required this.claveMateria,
    required this.materia,
    required this.ciclo,
    required this.calificacion,
    required this.enLetra,
    required this.estatus,
    required this.docente,
    this.recursada = '',
  });

  factory _CalifAdmin.fromMap(Map<String, dynamic> m) {
    return _CalifAdmin(
      fila: int.tryParse('${m['fila']}') ?? 0,
      programa: (m['programa'] ?? '').toString(),
      generacion: (m['generacion'] ?? '').toString(),
      grupo: (m['grupo'] ?? '').toString(),
      claveMateria: (m['claveMateria'] ?? '').toString(),
      materia: (m['materia'] ?? '').toString(),
      ciclo: (m['ciclo'] ?? '').toString(),
      calificacion: (m['calificacion'] ?? '').toString(),
      enLetra: (m['enLetra'] ?? '').toString(),
      estatus: (m['estatus'] ?? '').toString(),
      docente: (m['docente'] ?? '').toString(),
      recursada: (m['recursada'] ?? '').toString(),
    );
  }
}

// Un renglón para mostrar: una materia (del plan o no) y su calificación si
// existe. Si calif es null, está pendiente.
class _Fila {
  final String materia;
  final int ciclo;
  final _CalifAdmin? calif;
  const _Fila(this.materia, this.ciclo, this.calif);
  bool get pendiente => calif == null;
}

class _AdminCalificacionesScreenState extends State<AdminCalificacionesScreen> {
  final TextEditingController _matricula = TextEditingController();

  bool _buscando = false;
  bool _busquedaHecha = false;
  String? _error;
  String _busquedaMateria = '';
  Timer? _debounceMateria; // búsqueda con retardo

  // Alumno seleccionado (su matrícula real, aunque se haya buscado por nombre).
  String _matriculaSel = '';
  String _nombre = '';
  String _correo = '';
  String _programa = '';
  // Programas distintos que aparecen en SUS calificaciones, con cuántas filas
  // trae cada uno. Si son dos o más, el expediente está mezclado.
  List<Map<String, dynamic>> _programasEnCalif = [];
  String _generacion = '';
  List<_CalifAdmin> _califs = [];

  // Coincidencias cuando se busca por nombre.
  List<_Candidato> _candidatos = [];

  // (ago-22) Catálogo de docentes para adjudicar una calificación capturada
  // a mano. La columna 14 de la hoja Calificaciones guarda el nombre del
  // profesor, y de ahí sale su CURP en el paquete de SIGA: una fila sin
  // docente llega sin CURP y se cae en el corte.
  List<Map<String, dynamic>> _docentes = [];
  String _docentePredet = '';

  @override
  void initState() {
    super.initState();
    _cargarDocentes();
    final m = widget.matriculaInicial?.trim() ?? '';
    if (m.isNotEmpty) {
      _matricula.text = m;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _cargarAlumno(m, ''));
    }
  }

  Future<void> _cargarDocentes() async {
    try {
      final u = Uri.parse(guardianUrl)
          .replace(queryParameters: {'accion': 'docentes_calif_lista'});
      final r = await http.get(u).timeout(const Duration(seconds: 30));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true || !mounted) return;
      setState(() {
        _docentes = ((d['docentes'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _docentePredet =
            ((d['predeterminado'] as Map?)?['nombre'] ?? '').toString();
      });
    } catch (_) {
      // Sin catálogo la pantalla sigue sirviendo: el campo queda de texto libre.
    }
  }

  /// ¿Ese nombre tiene CURP registrada? Se avisa ANTES de guardar, no cuando
  /// SIGA rechace la fila tres meses después.
  bool _docenteSinCurp(String nombre) {
    final n = nombre.trim().toLowerCase();
    if (n.isEmpty) return false;
    for (final d in _docentes) {
      if ((d['nombre'] ?? '').toString().trim().toLowerCase() == n) {
        return d['tieneCurp'] != true;
      }
    }
    return true; // no está en la hoja Docentes: seguro no trae CURP
  }

  @override
  void dispose() {
    _matricula.dispose();
    _debounceMateria?.cancel();
    super.dispose();
  }

  // ---- Llamadas al Guardián ----

  // (2-sep) Una sola puerta para las consultas: espera el plazo que se le
  // pida y, si se vence o falla, reintenta UNA vez a los 2 segundos. Devuelve
  // null cuando de plano no hubo respuesta.
  Future<http.Response?> _pedirConReintento(Uri uri, Duration plazo) async {
    for (var intento = 0; intento < 2; intento++) {
      try {
        if (intento > 0) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
        final r = await http.get(uri).timeout(plazo);
        if (r.statusCode == 200) return r;
      } catch (_) {
        // Se reintenta una vez; si vuelve a fallar, se avisa arriba.
      }
    }
    return null;
  }


  // Paso 1: resolver el texto (matrícula o nombre) a un alumno.
  Future<void> _buscar() async {
    final q = _matricula.text.trim();
    if (q.isEmpty) {
      _aviso('Escribe una matrícula o un nombre para buscar.');
      return;
    }
    setState(() {
      _buscando = true;
      _error = null;
      _busquedaHecha = true;
      _candidatos = [];
      _matriculaSel = '';
      _califs = [];
    });
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'grupos_admin_buscar',
        'q': q,
      });
      // (2-sep) EL PLAZO DE 30 s ERA LA CAUSA DEL FALSO «revisa tu conexión».
      // Medido: esta búsqueda tarda ~9 s en un momento tranquilo, porque
      // recorre la base de Grupos completa. Cuando el Guardián trae cola
      // —lo normal a media mañana— se pasa de 30 s, salta al catch y la
      // pantalla culpa a la red aunque el internet esté perfecto. Ahora se
      // espera lo razonable y se reintenta una vez antes de rendirse.
      final resp = await _pedirConReintento(uri, const Duration(seconds: 75));
      if (resp == null) throw Exception('sin respuesta');
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      // Coincidencias por nombre/matrícula, sin repetir matrícula.
      final vistos = <String>{};
      final cands = <_Candidato>[];
      for (final e in (data['grupos'] as List<dynamic>? ?? [])) {
        final m = e as Map<String, dynamic>;
        final mat = (m['matricula'] ?? '').toString().trim();
        if (mat.isEmpty || vistos.contains(mat)) continue;
        vistos.add(mat);
        cands.add(_Candidato(
          mat,
          (m['nombre'] ?? '').toString(),
          (m['programa'] ?? '').toString(),
        ));
      }

      if (cands.length == 1) {
        await _cargarAlumno(cands.first.matricula, cands.first.nombre);
        return;
      }
      if (cands.isEmpty) {
        // Si escribió una matrícula, intentamos cargarla directo
        // (puede tener calificaciones aunque no esté en la base de grupos).
        final esMatricula = RegExp(r'^\d{4,}$').hasMatch(q);
        if (esMatricula) {
          await _cargarAlumno(q, '');
          return;
        }
        if (mounted) setState(() => _buscando = false);
        return;
      }
      if (mounted) {
        setState(() {
          _candidatos = cands;
          _buscando = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _buscando = false;
          _error =
              'El sistema tardó más de lo normal en responder. No es tu '
              'conexión: vuelve a intentarlo en un momento.';
        });
      }
    }
  }

  // Paso 2: cargar las calificaciones de un alumno por su matrícula.
  Future<void> _cargarAlumno(String matricula, String nombrePref) async {
    final mat = matricula.trim();
    if (mat.isEmpty) return;
    setState(() {
      _buscando = true;
      _error = null;
      _busquedaHecha = true;
      _candidatos = [];
    });
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'calif_admin_listar',
        'matricula': mat,
      });
      // (2-sep) Medido: ~13 s para un alumno, porque se recorre la hoja de
      // Calificaciones entera. Aquí NO se cachea a propósito: es la pantalla
      // donde se editan las notas, y servir datos guardados sería peor que
      // esperar.
      final resp = await _pedirConReintento(uri, const Duration(seconds: 90));
      if (resp == null) throw Exception('sin respuesta');
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'Respuesta inválida');
      }
      final lista = (data['calificaciones'] as List<dynamic>? ?? []);
      final califs = lista
          .map((e) => _CalifAdmin.fromMap(e as Map<String, dynamic>))
          .toList();
      if (mounted) {
        setState(() {
          _matriculaSel = mat;
          final n = (data['nombre'] ?? '').toString();
          _nombre = n.isNotEmpty ? n : nombrePref;
          _correo = (data['correo'] ?? '').toString();
          // (ago-22) EL PROGRAMA SALE DEL PADRÓN, NO DE LA MAYORÍA.
          // _masFrecuente clasificaba al alumno en el programa del que tuviera
          // MÁS calificaciones. Quien cambió de programa conserva las materias
          // del anterior, así que ésas ganan por número y la pantalla le pinta
          // el plan viejo: sus materias nuevas aparecen como sobrantes y las
          // del plan que ya no cursa, como pendientes. El padrón trae el
          // programa vigente. Sólo si el padrón no responde se cae a la
          // mayoría, que es mejor que quedarse sin plan.
          final progPad = (data['programaPadron'] ?? '').toString().trim();
          final genPad = (data['generacionPadron'] ?? '').toString().trim();
          _programa = progPad.isNotEmpty
              ? progPad
              : _masFrecuente(califs.map((c) => c.programa));
          _generacion = genPad.isNotEmpty
              ? genPad
              : _masFrecuente(califs.map((c) => c.generacion));
          _programasEnCalif = ((data['programasEnCalif'] as List?) ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _califs = califs;
          _buscando = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _buscando = false;
          _error =
              'El sistema tardó más de lo normal en responder. No es tu '
              'conexión: vuelve a intentarlo en un momento.';
        });
      }
    }
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> payload) async {
    final resp = await http
        .post(
          Uri.parse(guardianUrl),
          headers: {'Content-Type': 'text/plain;charset=utf-8'},
          body: jsonEncode(payload),
        )
        .timeout(Duration(seconds: 60));
    if (resp.statusCode != 200) {
      throw Exception('El servidor respondió ${resp.statusCode}.');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    if (data['ok'] != true) {
      throw Exception(data['error'] ?? 'El Guardián reportó un error.');
    }
    return data;
  }

  // Captura/edición. Si [base] viene, edita esa fila; si no, agrega.
  Future<void> _guardar({
    _CalifAdmin? base,
    String? materiaPrefill,
    int? cicloPrefill,
  }) async {
    final datos = await _dialogoFormulario(
      titulo: base != null ? 'Corregir calificación' : 'Capturar calificación',
      base: base,
      materiaPrefill: materiaPrefill,
      cicloPrefill: cicloPrefill,
    );
    if (datos == null) return;
    setState(() => _buscando = true);
    try {
      Map<String, dynamic> res;
      if (base != null) {
        res = await _post({
          'accion': 'calif_admin_editar',
          'fila': base.fila,
          'matricula': _matriculaSel,
          'programa': datos['programa'],
          'generacion': datos['generacion'],
          'grupo': datos['grupo'],
          'claveMateria': datos['claveMateria'],
          'materia': datos['materia'],
          'ciclo': datos['ciclo'],
          'calificacion': datos['calificacion'],
          'docente': datos['docente'],
          'recursada': datos['recursada'],
        });
      } else {
        res = await _post({
          'accion': 'calif_admin_agregar',
          'matricula': _matriculaSel,
          'nombre': _nombre,
          'correo': _correo,
          'programa': datos['programa'],
          'generacion': datos['generacion'],
          'grupo': datos['grupo'],
          'claveMateria': datos['claveMateria'],
          'materia': datos['materia'],
          'ciclo': datos['ciclo'],
          'calificacion': datos['calificacion'],
          'docente': datos['docente'],
        });
      }
      if (res.containsKey('modoPrueba') || res.containsKey('guardadas')) {
        throw Exception(
            'El Guardián todavía no tiene las funciones de edición. Sube el '
            'Code.gs actualizado y publica una versión nueva (Implementar → '
            'Administrar implementaciones → Nueva versión).');
      }
      final avisoServidor = (res['aviso'] ?? '').toString();
      _aviso(avisoServidor.isNotEmpty
          ? avisoServidor
          : base != null
              ? 'Calificación actualizada en la base.'
              : 'Calificación guardada en la base.');
      await _cargarAlumno(_matriculaSel, _nombre);
    } catch (e) {
      if (mounted) setState(() => _buscando = false);
      _aviso('No se pudo guardar: $e');
    }
  }

  Future<void> _eliminar(_CalifAdmin c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Borrar calificación'),
        content: Text(
          '¿Seguro que deseas borrar esta calificación?\n\n'
          '${c.materia}\nCalificación: ${c.calificacion}\n\n'
          'Esta acción no se puede deshacer.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: cessumRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Borrar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _buscando = true);
    try {
      await _post({
        'accion': 'calif_admin_eliminar',
        'fila': c.fila,
        'matricula': _matriculaSel,
      });
      _aviso('Calificación borrada de la base.');
      await _cargarAlumno(_matriculaSel, _nombre);
    } catch (e) {
      if (mounted) setState(() => _buscando = false);
      _aviso('No se pudo borrar: $e');
    }
  }

  // Marca la materia como NO cursada: conserva el renglón pero limpia la
  // calificación, de modo que deje de contar como reprobada y pase a pendiente.
  // Útil para alumnos que regresan de baja temporal.
  Future<void> _marcarNoCursada(_CalifAdmin c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Marcar como NO cursada'),
        content: Text(
          'Se quitará la calificación de:\n\n'
          '${c.materia}\nCalificación actual: ${c.calificacion}\n\n'
          'La materia quedará como pendiente / no cursada y dejará de contar '
          'como reprobada. Podrás capturar su calificación más adelante.',
          style: TextStyle(height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: cessumGold,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Marcar no cursada'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _buscando = true);
    try {
      final res = await _post({
        'accion': 'calif_admin_no_cursada',
        'fila': c.fila,
        'matricula': _matriculaSel,
      });
      if (res.containsKey('modoPrueba') || res.containsKey('guardadas')) {
        throw Exception(
            'El Guardián todavía no tiene esta función. Sube el Code.gs '
            'actualizado y publica una versión nueva.');
      }
      _aviso('Materia marcada como no cursada.');
      await _cargarAlumno(_matriculaSel, _nombre);
    } catch (e) {
      if (mounted) setState(() => _buscando = false);
      _aviso('No se pudo: $e');
    }
  }

  Future<Map<String, String>?> _dialogoFormulario({
    required String titulo,
    _CalifAdmin? base,
    String? materiaPrefill,
    int? cicloPrefill,
  }) async {
    final programa = TextEditingController(
        text: base?.programa ?? (_programa.isNotEmpty ? _programa : ''));
    final generacion = TextEditingController(
        text: _genLimpia(base?.generacion ?? _generacion));
    final grupo = TextEditingController(text: base?.grupo ?? '');
    final clave = TextEditingController(text: base?.claveMateria ?? '');
    final materia =
        TextEditingController(text: base?.materia ?? materiaPrefill ?? '');
    final ciclo = TextEditingController(
        text: base?.ciclo ?? (cicloPrefill != null ? '$cicloPrefill' : ''));
    final calif = TextEditingController(text: base?.calificacion ?? '');
    // (ago-22) A quién se le adjudica. Al editar se respeta el que ya tenía;
    // al capturar de cero, Vicerrectoría por omisión.
    final docente = TextEditingController(
        text: (base?.docente ?? '').trim().isNotEmpty
            ? base!.docente.trim()
            : _docentePredet);
    var recursada = (base?.recursada ?? '').toUpperCase() == 'SI';

    Widget campo(TextEditingController c, String etq, {TextInputType? tipo}) {
      return Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: c,
          keyboardType: tipo,
          decoration: InputDecoration(
            labelText: etq,
            border: OutlineInputBorder(),
            isDense: true,
            contentPadding:
                EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      );
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Quedará con estatus "Validada" y se guarda en la base.',
                  style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                ),
              ),
              SizedBox(height: 12),
              campo(materia, 'Materia'),
              campo(calif, 'Calificación (número)',
                  tipo: TextInputType.numberWithOptions(decimal: true)),
              campo(ciclo, 'Ciclo (1, 2, 3, 4...)',
                  tipo: TextInputType.number),
              campo(programa, 'Programa'),
              campo(generacion, 'Generación (ej. 25-3)'),
              campo(grupo, 'Grupo (opcional)'),
              // (ago-22) SELECTOR CON BÚSQUEDA. Se escribe y filtra; si el
              // docente no está en la hoja Docentes se puede teclear igual,
              // pero se avisa que esa fila irá sin CURP a SIGA.
              StatefulBuilder(
                builder: (ctx3, setDoc) {
                  final sinCurp = _docenteSinCurp(docente.text);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RawAutocomplete<String>(
                        textEditingController: docente,
                        focusNode: FocusNode(),
                        optionsBuilder: (v) {
                          final q = v.text.trim().toLowerCase();
                          final todos = _docentes
                              .map((d) => (d['nombre'] ?? '').toString())
                              .where((s) => s.isNotEmpty);
                          if (q.isEmpty) return todos.take(12);
                          return todos
                              .where((s) => s.toLowerCase().contains(q))
                              .take(12);
                        },
                        onSelected: (v) => setDoc(() {}),
                        fieldViewBuilder: (c, ctrl, focus, onSubmit) =>
                            Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: TextField(
                            controller: ctrl,
                            focusNode: focus,
                            onChanged: (_) => setDoc(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Docente al que se adjudica',
                              helperText:
                                  'Escribe para buscar. De este nombre sale la '
                                  'CURP del profesor en SIGA.',
                              helperMaxLines: 2,
                              border: OutlineInputBorder(),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 12),
                            ),
                          ),
                        ),
                        optionsViewBuilder: (c, onSel, opciones) => Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 4,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                  maxHeight: 220, maxWidth: 420),
                              child: ListView(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                children: opciones
                                    .map((o) => ListTile(
                                          dense: true,
                                          title: Text(o,
                                              style: const TextStyle(
                                                  fontSize: 13)),
                                          trailing: _docenteSinCurp(o)
                                              ? const Icon(Icons.warning_amber,
                                                  size: 16,
                                                  color: Color(0xFFB07D12))
                                              : null,
                                          onTap: () => onSel(o),
                                        ))
                                    .toList(),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (sinCurp && docente.text.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                              'Ese docente no tiene CURP registrada en la hoja '
                              'Docentes: esta calificación se caerá en el corte '
                              'de SIGA.',
                              style: const TextStyle(
                                  fontSize: 11,
                                  height: 1.3,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFB07D12))),
                        )
                      else
                        const SizedBox(height: 8),
                    ],
                  );
                },
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Text(
                    'La clave de la materia se asigna automáticamente.',
                    style: TextStyle(fontSize: 11, color: cessumFaint(context)),
                  ),
                ),
              ),
              StatefulBuilder(
                builder: (ctx2, setLocal) => SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: cessumRed,
                  value: recursada,
                  onChanged: (v) => setLocal(() => recursada = v),
                  title: Text('RECURSADA (reprobada en primera instancia)',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      'Cierra la titulación por Excelencia académica y la '
                      'mención honorífica (arts. 71-I y 85-II del Reglamento).',
                      style: TextStyle(fontSize: 10.5)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: cessumRed,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (materia.text.trim().isEmpty || calif.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content:
                        Text('La materia y la calificación son obligatorias.'),
                  ),
                );
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: Text('Guardar'),
          ),
        ],
      ),
    );

    if (ok != true) return null;
    return {
      'programa': programa.text.trim(),
      'generacion': generacion.text.trim(),
      'grupo': grupo.text.trim(),
      'claveMateria': clave.text.trim(),
      'materia': materia.text.trim(),
      'ciclo': ciclo.text.trim(),
      'calificacion': calif.text.trim(),
      'docente': docente.text.trim(),
      'recursada': recursada ? 'SI' : '',
    };
  }

  void _aviso(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: Duration(seconds: 3)),
    );
  }

  // Muestra la generación solo si es un texto corto y limpio (no una fecha
  // ni un timestamp ISO como 2026-03-25T07:00:00.000Z).
  String _genLimpia(String g) {
    final t = g.trim();
    if (t.isEmpty || t.length > 10) return '';
    if (t.contains(':') || t.toUpperCase().contains('GMT')) return '';
    if (RegExp(r'\d{4}-\d{2}-\d{2}').hasMatch(t)) return '';
    return t;
  }

  // ---- Helpers de plan ----
  String _masFrecuente(Iterable<String> xs) {
    final cuenta = <String, int>{};
    for (final x in xs) {
      final v = x.trim();
      if (v.isEmpty) continue;
      cuenta[v] = (cuenta[v] ?? 0) + 1;
    }
    String mejor = '';
    int max = 0;
    cuenta.forEach((k, v) {
      if (v > max) {
        max = v;
        mejor = k;
      }
    });
    return mejor;
  }

  String _norm(String s) {
    s = s.toLowerCase();
    const con = 'áàäâãéèëêíìïîóòöôõúùüûñ';
    const sin = 'aaaaaeeeeiiiiooooouuuun';
    for (var i = 0; i < con.length; i++) {
      s = s.replaceAll(con[i], sin[i]);
    }
    return s.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  // Igual que _norm, pero además ignora palabras de enlace ("de", "la", "el"…).
  // Sirve SOLO para emparejar el plan con su calificación: así una diferencia
  // mínima de redacción ("Fundamentos de Psicología" vs "Fundamentos de la
  // Psicología") deja de duplicar la materia. El nombre que se MUESTRA no cambia.
  String _normMat(String s) {
    s = s.toLowerCase();
    const con = 'áàäâãéèëêíìïîóòöôõúùüûñ';
    const sin = 'aaaaaeeeeiiiiooooouuuun';
    for (var i = 0; i < con.length; i++) {
      s = s.replaceAll(con[i], sin[i]);
    }
    const enlaces = {
      'de', 'del', 'la', 'el', 'los', 'las', 'y', 'e', 'en',
      'a', 'al', 'un', 'una', 'para', 'con'
    };
    final palabras = s
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.isNotEmpty && !enlaces.contains(w));
    return palabras.join();
  }

  String _claveProg(String prog) {
    final p = _norm(prog);
    if (p.contains('psicopedagog')) return 'psicopedagogia';
    if (p.contains('doctorado') && p.contains('ciencias')) return 'dce';
    if (p.contains('cienciasdelaeducacion')) return 'dce';
    if (p.contains('doctorado')) return 'doctoradoeducacion';
    if (p.contains('inclusiv')) return 'inclusiva';
    if (p.contains('pedagog')) return 'pedagogia';
    if (p.contains('educacion')) return 'educacion';
    return p;
  }

  /// (ago-21) EL PLAN DE **CUALQUIER** PROGRAMA, NO SOLO EL ACTUAL.
  ///
  /// Hay alumnos que egresaron de un programa y siguieron en otro —Bladimir,
  /// Dafne, Rosa Briseida y unos veinte más—. Sus materias del programa
  /// anterior no encajaban en el plan del actual y caían todas en «Otras
  /// materias», como si fueran basura.
  ///
  /// No lo eran: son su historial. Ahora se busca el plan del programa que
  /// trae CADA calificación, no el del alumno.
  List<List<String>>? _buscarPlanDe(String programa, String generacion) {
    final cp = _claveProg(programa);
    if (cp.isEmpty) return null;
    List<List<String>>? mismaGen;
    List<List<String>>? masGrande;
    planesEstudio.forEach((k, v) {
      final partes = k.split('||');
      if (partes.isEmpty) return;
      if (_claveProg(partes[0]) != cp) return;
      if (generacion.isNotEmpty &&
          partes.length > 1 &&
          partes[1] == generacion) {
        mismaGen = v;
      }
      if (masGrande == null || v.length > masGrande!.length) masGrande = v;
    });
    return mismaGen ?? masGrande;
  }

  List<List<String>>? _buscarPlan() {
    final cp = _claveProg(_programa);
    if (cp.isEmpty) return null;
    List<List<String>>? mismaGen;
    List<List<String>>? masGrande;
    planesEstudio.forEach((k, v) {
      final partes = k.split('||');
      if (partes.isEmpty) return;
      if (_claveProg(partes[0]) != cp) return;
      if (_generacion.isNotEmpty &&
          partes.length > 1 &&
          partes[1] == _generacion) {
        mismaGen = v;
      }
      if (masGrande == null || v.length > masGrande!.length) masGrande = v;
    });
    return mismaGen ?? masGrande;
  }

  bool get _esTrimestral {
    final p = _norm(_programa);
    if (!p.contains('educacion')) return false;
    const excluir = [
      'inclusiv',
      'doctorado',
      'pedagog',
      'psicopedagog',
      'ciencias',
      'enfasis',
      'investigacion'
    ];
    for (final e in excluir) {
      if (p.contains(e)) return false;
    }
    return true;
  }

  String _tituloPeriodo(int n) {
    final unidad = _esTrimestral ? 'trimestre' : 'semestre';
    const ordinal = {
      1: 'Primer',
      2: 'Segundo',
      3: 'Tercer',
      4: 'Cuarto',
      5: 'Quinto',
      6: 'Sexto',
      7: 'Séptimo',
      8: 'Octavo'
    };
    final o = ordinal[n];
    // (ago-22) El ciclo 0 no es un cajón de basura: ahí caen las materias que
    // el alumno cursó fuera de su plan vigente — formación continua de otro
    // posgrado, o materias del plan anterior si cambió de programa. Llamarlas
    // "Otras materias" hacía pensar que sobraban.
    if (o == null) {
      return n <= 0 ? 'Cursadas fuera de su plan vigente' : 'Ciclo $n';
    }
    return '$o $unidad';
  }

  // Combina el plan con las calificaciones existentes.
  // Empareja por FILA (no por nombre) para que las calificaciones DUPLICADAS o
  // con nombre variante (p. ej. "Diseño universal DEL aprendizaje." frente al
  // plan "...PARA EL aprendizaje") NO se oculten: la casilla del plan toma una
  // y las filas sobrantes se muestran en "Otras materias" para poder BORRARLAS.
  Map<int, List<_Fila>> _porCiclo() {
    final mapa = <int, List<_Fila>>{};
    // (ago-22, criterio de Vicerrectoría) EL PLAN ES UNO SOLO: EL DEL PADRÓN.
    //
    // El 21 de agosto se juntaron los planes de todos los programas donde el
    // alumno tuviera calificaciones, para que sus materias anteriores no
    // cayeran en «Otras materias». Fue peor: entraban materias de OTRO plan
    // que el alumno nunca llevó y, sin calificación, se pintaban como
    // «Pendiente» — deuda inventada.
    //
    // Y hay una razón de fondo por la que juntar planes nunca puede estar
    // bien: en las primeras generaciones los alumnos podían cursar materias
    // de otros posgrados como FORMACIÓN CONTINUA. Esas calificaciones existen
    // en actas, pero NO son asignaturas de un plan suyo: no se les debe exigir
    // el resto de ese plan ni contárselas como avance.
    //
    // Regla: el plan que se pinta es el del programa vigente en el padrón, y
    // nada más. Toda calificación que no case con ese plan se muestra íntegra
    // abajo, en su propia sección, con el programa del que viene.
    final plan = _buscarPlanDe(_programa, _generacion) ?? _buscarPlan();

    // Agrupa TODAS las calificaciones por nombre normalizado (puede haber varias).
    final porNombre = <String, List<_CalifAdmin>>{};
    for (final c in _califs) {
      final k = _normMat(c.materia);
      if (k.isNotEmpty) (porNombre[k] ??= []).add(c);
    }
    final filasMostradas = <int>{}; // por identidad de fila, no por nombre

    bool esValidada(_CalifAdmin c) => c.estatus.toLowerCase().trim() == 'validada';

    if (plan != null) {
      for (final fila in plan) {
        final ciclo = int.tryParse(fila[0]) ?? 0;
        final materia = fila[1];
        final k = _normMat(materia);
        final candidatas = porNombre[k] ?? const <_CalifAdmin>[];
        // La casilla del plan toma la MEJOR fila aún no usada: primero Validada,
        // luego la que tenga clave, luego la primera disponible.
        _CalifAdmin? elegida;
        for (final c in candidatas) {
          if (filasMostradas.contains(c.fila)) continue;
          final e = elegida;
          if (e == null) {
            elegida = c;
            continue;
          }
          final mejora = (esValidada(c) && !esValidada(e)) ||
              (esValidada(c) == esValidada(e) &&
                  c.claveMateria.trim().isNotEmpty &&
                  e.claveMateria.trim().isEmpty);
          if (mejora) elegida = c;
        }
        if (elegida != null) filasMostradas.add(elegida.fila);
        mapa.putIfAbsent(ciclo, () => []).add(_Fila(materia, ciclo, elegida));
      }
    }
    // Toda calificación cuya FILA no entró al plan se muestra igual, agrupada en
    // "Otras materias" (ciclo 0), con su botón Borrar. Así aparecen los
    // duplicados o las materias fuera del plan y se pueden eliminar.
    for (final c in _califs) {
      if (filasMostradas.contains(c.fila)) continue;
      mapa.putIfAbsent(0, () => []).add(_Fila(c.materia, 0, c));
      filasMostradas.add(c.fila);
    }
    return mapa;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: Text('Editar calificaciones'),
      ),
      floatingActionButton:
          (_matriculaSel.isNotEmpty && _error == null && !_buscando)
              ? FloatingActionButton.extended(
                  backgroundColor: cessumRed,
                  foregroundColor: Colors.white,
                  onPressed: () => _guardar(),
                  icon: Icon(Icons.add),
                  label: Text('Otra materia'),
                )
              : null,
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _matricula,
                    keyboardType: TextInputType.text,
                    onSubmitted: (_) => _buscar(),
                    decoration: InputDecoration(
                      hintText: 'Matrícula o nombre del alumno',
                      prefixIcon: Icon(Icons.search),
                      filled: true,
                      fillColor: cessumEsOscuro(context) ? const Color(0xFF211F1D) : Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 10),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cessumRed,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _buscando ? null : _buscar,
                    child: Text('Buscar'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _cuerpo()),
        ],
      ),
    );
  }

  Widget _cuerpo() {
    if (_buscando) {
      return Center(child: CircularProgressIndicator(color: cessumRed));
    }
    if (_error != null) return _vistaError();
    if (!_busquedaHecha) return _vistaInicial();
    if (_matriculaSel.isEmpty) {
      if (_candidatos.isNotEmpty) return _vistaCandidatos();
      return _vistaSinCoincidencias();
    }
    return _vistaResultados();
  }

  Widget _vistaCandidatos() {
    return ListView(
      padding: EdgeInsets.all(16),
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 8, left: 4),
          child: Text(
            'Coincidencias. Toca un alumno para ver y editar sus calificaciones:',
            style: TextStyle(color: cessumMuted(context), fontSize: 13),
          ),
        ),
        ..._candidatos.map(
          (c) => Container(
            margin: EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: cessumEsOscuro(context) ? Theme.of(context).cardColor : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
            ),
            child: ListTile(
              leading: Icon(Icons.person, color: cessumRed),
              title: Text(c.nombre.isNotEmpty ? c.nombre : '(sin nombre)',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                'Matrícula: ${c.matricula}'
                '${c.programa.isNotEmpty ? '  ·  ${c.programa}' : ''}',
                style: TextStyle(fontSize: 12),
              ),
              trailing: Icon(Icons.chevron_right, color: cessumRed),
              onTap: () => _cargarAlumno(c.matricula, c.nombre),
            ),
          ),
        ),
      ],
    );
  }

  Widget _vistaSinCoincidencias() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, color: cessumFaint(context), size: 52),
            SizedBox(height: 12),
            Text(
              'No encontramos a nadie con esa matrícula o nombre.\n'
              'Revisa que esté inscrito en un grupo o usa la matrícula exacta.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cessumMuted(context), height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vistaInicial() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.manage_search, color: cessumFaint(context), size: 56),
            SizedBox(height: 14),
            Text(
              'Busca a un alumno por matrícula o nombre para ver todas sus '
              'materias y capturar o corregir calificaciones.',
              textAlign: TextAlign.center,
              style: TextStyle(color: cessumMuted(context), height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vistaResultados() {
    final grupos = _porCiclo();
    final q = _busquedaMateria.trim().toLowerCase();
    final totalMaterias =
        grupos.values.fold<int>(0, (a, b) => a + b.length);
    // Filtra por materia conservando la agrupación por ciclo.
    final gruposVis = <int, List<_Fila>>{};
    grupos.forEach((ciclo, filas) {
      final fs = q.isEmpty
          ? filas
          : filas
              .where((f) => f.materia.toLowerCase().contains(q))
              .toList();
      if (fs.isNotEmpty) gruposVis[ciclo] = fs;
    });
    final ciclos = gruposVis.keys.toList()
      ..sort((a, b) {
        // "Otras materias" (ciclo 0 o menor) siempre al final.
        final aa = a <= 0 ? 9999 : a;
        final bb = b <= 0 ? 9999 : b;
        return aa.compareTo(bb);
      });

    return ListView(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 90),
      children: [
        Container(
          padding: EdgeInsets.all(16),
          margin: EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: cessumRed.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.person, color: cessumRed, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _nombre.isNotEmpty ? _nombre : '(sin nombre en la base)',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: cessumInk(context),
                      ),
                    ),
                    Text(
                      'Matrícula: $_matriculaSel'
                      '${_programa.isNotEmpty ? '  ·  $_programa' : ''}',
                      style:
                          TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_programasEnCalif.length > 1) ...[
          // (ago-22) EXPEDIENTE MEZCLADO. El alumno tiene calificaciones en más
          // de un programa —casi siempre porque cambió— y el plan que se pinta
          // abajo es el del padrón. Las materias del otro plan van a verse como
          // sobrantes y las de éste como pendientes. Decirlo aquí evita que
          // alguien "corrija" un expediente que no está mal, solo mezclado.
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFB07D12).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFB07D12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.call_split, size: 17, color: Color(0xFFB07D12)),
                  SizedBox(width: 7),
                  Text('Expediente con materias de más de un programa',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF8A5A00))),
                ]),
                const SizedBox(height: 6),
                ..._programasEnCalif.map((e) {
                  final nom = (e['programa'] ?? '').toString();
                  final filas = (e['filas'] ?? 0).toString();
                  final esSuyo = nom.trim().toLowerCase() ==
                      _programa.trim().toLowerCase();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                        '·  $nom — $filas materia(s)'
                        '${esSuyo ? '  ← el del padrón' : ''}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight:
                                esSuyo ? FontWeight.w700 : FontWeight.w400,
                            color: const Color(0xFF8A5A00))),
                  );
                }),
                const SizedBox(height: 6),
                Text(
                    'El plan que se muestra abajo es SOLO el de $_programa, su '
                    'programa vigente en el padrón. Lo demás aparece abajo en '
                    '«Cursadas fuera de su plan vigente»: pueden ser materias '
                    'de formación continua de otro posgrado o de un plan '
                    'anterior. Cuentan como historial, no como avance de este '
                    'plan, y no se le exige el resto de ese otro plan.',
                    style: const TextStyle(
                        fontSize: 11.5, height: 1.35, color: Color(0xFF8A5A00))),
              ],
            ),
          ),
        ],
        if (totalMaterias > 6) ...[
          TextField(
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Buscar materia',
              prefixIcon: Icon(Icons.search, size: 20),
              suffixIcon: _busquedaMateria.isEmpty
                  ? null
                  : IconButton(
                      icon: Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _busquedaMateria = ''),
                    ),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onChanged: (v) {
              _debounceMateria?.cancel();
              _debounceMateria =
                  Timer(Duration(milliseconds: 300), () {
                if (mounted) setState(() => _busquedaMateria = v);
              });
            },
          ),
          SizedBox(height: 12),
        ],
        if (ciclos.isEmpty)
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cessumEsOscuro(context) ? Theme.of(context).cardColor : Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Icon(Icons.inbox, color: cessumFaint(context), size: 40),
                SizedBox(height: 10),
                Text(
                  _busquedaMateria.trim().isNotEmpty
                      ? 'Ninguna materia coincide con la búsqueda.'
                      : 'No encontramos el plan de este alumno. Usa "Otra materia" '
                          'para capturar manualmente.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cessumMuted(context), height: 1.4),
                ),
              ],
            ),
          )
        else
          ...ciclos.map((c) => _seccionCiclo(c, gruposVis[c]!)),
      ],
    );
  }

  Widget _seccionCiclo(int ciclo, List<_Fila> filas) {
    return Container(
      margin: EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: cessumEsOscuro(context) ? Theme.of(context).cardColor : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: cessumRed.withValues(alpha: 0.08),
            child: Text(
              _tituloPeriodo(ciclo),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: cessumInk(context),
              ),
            ),
          ),
          ...filas.map((f) => _renglon(f, ciclo)),
        ],
      ),
    );
  }

  Widget _renglon(_Fila f, int ciclo) {
    final c = f.calif;
    final numero =
        c == null ? null : double.tryParse(c.calificacion.replaceAll(',', '.'));
    final reprobada = numero != null && numero < 7;
    // Sin nota = pendiente (sin renglón) o renglón "No cursada" (calif vacía).
    final sinNota = c == null || c.calificacion.trim().isEmpty;
    final Color color = sinNota
        ? cessumFaint(context)
        : (reprobada ? cessumRed : _verdeOk);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              sinNota ? '—' : c!.calificacion,
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800, color: color),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f.materia,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: f.pendiente ? cessumMuted(context) : cessumInk(context),
                    height: 1.25,
                  ),
                ),
                if ((c?.recursada ?? '').toUpperCase() == 'SI')
                  Container(
                    margin: EdgeInsets.only(top: 3),
                    padding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Color(0xFFE65100).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: Color(0xFFE65100).withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      '🔁 RECURSADA · sin Excelencia académica',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFE65100)),
                    ),
                  ),
                SizedBox(height: 2),
                // (ago-22) En la sección de fuera del plan, el nombre de la
                // materia no basta: hay que saber de qué programa viene, si no
                // parece un dato suelto. Ahí es dato, no adorno.
                if (ciclo <= 0 && (c?.programa ?? '').trim().isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(bottom: 2),
                    child: Text(c!.programa.trim(),
                        style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: cessumMuted(context))),
                  ),
                Text(
                  f.pendiente
                      ? 'Pendiente'
                      : (c!.estatus.isNotEmpty ? c.estatus : 'Validada'),
                  style: TextStyle(
                    fontSize: 12,
                    color: f.pendiente ? cessumFaint(context) : cessumMuted(context),
                  ),
                ),
              ],
            ),
          ),
          if (f.pendiente)
            TextButton.icon(
              onPressed: () =>
                  _guardar(materiaPrefill: f.materia, cicloPrefill: ciclo),
              icon: Icon(Icons.add, size: 18, color: cessumRed),
              label: Text('Capturar',
                  style: TextStyle(color: cessumRed, fontSize: 13)),
            )
          else ...[
            OutlinedButton.icon(
              onPressed: () => _guardar(base: c),
              icon: Icon(Icons.edit, size: 16, color: cessumRed),
              label: Text('Editar',
                  style: TextStyle(color: cessumRed, fontSize: 13)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: cessumRed),
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size(0, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            if (numero != null)
              IconButton(
                icon: Icon(Icons.event_busy, size: 20, color: cessumGold),
                tooltip: 'Marcar como no cursada',
                onPressed: () => _marcarNoCursada(c!),
              ),
            IconButton(
              icon:
                  Icon(Icons.delete_outline, size: 20, color: cessumRed),
              tooltip: 'Borrar',
              onPressed: () => _eliminar(c!),
            ),
          ],
        ],
      ),
    );
  }

  Widget _vistaError() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off, color: cessumFaint(context), size: 48),
            SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: cessumMuted(context), height: 1.4),
            ),
            SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed,
                foregroundColor: Colors.white,
              ),
              onPressed: _buscar,
              icon: Icon(Icons.refresh),
              label: Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
