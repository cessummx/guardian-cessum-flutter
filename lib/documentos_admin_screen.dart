import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'alumnos_service.dart';
import 'auth/session_store.dart';

/// Generación de documentos oficiales (admin).
///
/// (3-sep) Ampliada. Antes había que teclear la matrícula de memoria y solo
/// se podían emitir dos tipos, aunque el Guardián sabe hacer siete. Ahora se
/// busca al alumno por nombre o matrícula, sus datos se cargan solos, y se
/// puede ver el documento ANTES de emitirlo con folio: la vista previa no
/// consume folio ni queda registrada, así que se puede revisar cuantas veces
/// haga falta.
///
/// El documento NO se le manda al alumno: se genera, se registra y se
/// descarga aquí. Enviarlo es una decisión aparte, de quien lo emite.
class DocumentosAdminScreen extends StatefulWidget {
  const DocumentosAdminScreen({super.key});

  @override
  State<DocumentosAdminScreen> createState() => _DocumentosAdminScreenState();
}

/// Los siete tipos que el Guardián sabe construir.
class _TipoDoc {
  final String clave;
  final String nombre;
  final String pista;
  final IconData icono;
  const _TipoDoc(this.clave, this.nombre, this.pista, this.icono);
}

const List<_TipoDoc> _tiposDoc = [
  _TipoDoc('constancia', 'Constancia de estudios',
      'Acredita que el alumno cursa el programa. Es la que piden en el trabajo.',
      Icons.description_outlined),
  _TipoDoc('inscripcion', 'Constancia de inscripción',
      'Acredita la inscripción al ciclo, sin detalle de calificaciones.',
      Icons.how_to_reg_outlined),
  _TipoDoc('kardex', 'Kárdex de calificaciones',
      'Todas las asignaturas acreditadas con calificación, créditos y periodo.',
      Icons.grid_on_outlined),
  _TipoDoc('certificado', 'Certificado parcial',
      'Documento formal de las materias cursadas hasta hoy.',
      Icons.workspace_premium_outlined),
  _TipoDoc('pasante', 'Carta de pasante',
      'Para quien terminó las materias y aún no se titula.',
      Icons.school_outlined),
  _TipoDoc('terminacion', 'Carta de terminación',
      'Acredita la conclusión del plan de estudios.',
      Icons.task_alt_outlined),
  _TipoDoc('noadeudo', 'Carta de no adeudo',
      'Solo si el alumno está al corriente. Confirme el estado de cuenta antes.',
      Icons.account_balance_wallet_outlined),
  // (5-oct-2026) Para becas y crédito educativo (IBCEES y financieras).
  _TipoDoc('costos', 'Carta de costos del programa',
      'Costo del programa según el plan de pagos de su generación; si tiene beca, la muestra aparte. Para créditos educativos.',
      Icons.request_quote_outlined),
  _TipoDoc('beca', 'Constancia de beca institucional',
      'Si tiene beca CESSUM activa, su porcentaje y desde cuándo; si no, que no cuenta con una. La piden las becas estatales.',
      Icons.volunteer_activism_outlined),
];

class _DocumentosAdminScreenState extends State<DocumentosAdminScreen> {
  final _busqueda = TextEditingController();
  final _matricula = TextEditingController();
  final _nombre = TextEditingController();
  final _semestre = TextEditingController();
  final _generacion = TextEditingController();

  String _tipo = 'constancia';
  String? _programa;
  String? _modalidad;
  bool _firmar = true;
  bool _generando = false;
  bool _previendo = false;

  List<AlumnoInfo> _todos = [];
  bool _cargandoAlumnos = true;
  AlumnoInfo? _elegido;

  String? _folio;
  String? _urlPdf;
  String? _urlDocx;

  // ── (21-sep) MODO DOCENTE ─────────────────────────────────────────────
  // La pantalla era solo de trámites de alumnos. La constancia de trabajo del
  // profesor ya la sabía hacer el Guardián —una por cada materia impartida,
  // con horas, modalidad y periodo tomados de la asignación— pero no había
  // dónde pedirla. Ahora hay un selector arriba: documentos de alumnos o de
  // docentes. Cada uno con su propio flujo, sin mezclarse.
  String _modo = 'alumno';
  final _buscaDoc = TextEditingController();
  List<Map<String, dynamic>> _docentes = [];
  bool _cargandoDocentes = false;
  bool _docentesCargados = false;
  Map<String, dynamic>? _docenteSel;
  List<Map<String, dynamic>> _materiasDoc = [];
  bool _cargandoMaterias = false;
  String? _avisoMaterias;
  Map<String, dynamic>? _materiaSel;
  bool _generandoDoc = false;
  String? _folioDoc;
  String? _pdfDoc;
  String? _errorDoc;

  // ── (21-sep) CAPTURA MANUAL ──────────────────────────────────────────
  // Para materias impartidas antes de que existiera la app: no están en las
  // asignaciones ni tienen acta en el sistema, así que los datos se teclean.
  // El documento sale con el mismo formato, firma y folio.
  String _fuenteDoc = 'sistema'; // 'sistema' | 'manual'
  final _mDocente = TextEditingController();
  final _mMateria = TextEditingController();
  final _mProgramaOtro = TextEditingController();
  final _mHoras = TextEditingController();
  String _mArticulo = 'auto';
  String? _mPrograma;
  String _mModalidad = 'No escolarizada';
  DateTime? _mInicio;
  DateTime? _mTermino;

  _TipoDoc get _tipoActual =>
      _tiposDoc.firstWhere((t) => t.clave == _tipo, orElse: () => _tiposDoc.first);

  @override
  void initState() {
    super.initState();
    _cargarAlumnos();
  }

  @override
  void dispose() {
    for (final c in [_busqueda, _matricula, _nombre, _semestre, _generacion,
        _buscaDoc, _mDocente, _mMateria, _mProgramaOtro, _mHoras]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _cargarAlumnos() async {
    try {
      final lista = await AlumnosService.listarAlumnos();
      if (!mounted) return;
      setState(() {
        _todos = lista;
        _cargandoAlumnos = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _cargandoAlumnos = false);
    }
  }

  /// Al elegir alumno se llenan los campos con lo que ya sabe el sistema, para
  /// no teclear a mano lo que la base tiene bien. Quedan editables por si un
  /// caso concreto necesita otra cosa.
  void _tomar(AlumnoInfo a) {
    setState(() {
      _elegido = a;
      _matricula.text = a.matricula;
      _nombre.text = a.nombre;
      _generacion.text = a.generacion;
      _programa = a.programa.isEmpty ? null : a.programa;
      _modalidad = a.modalidad.isEmpty ? null : a.modalidad;
      _folio = null;
      _urlPdf = null;
      _urlDocx = null;
      _busqueda.clear();
    });
  }

  List<AlumnoInfo> get _coincidencias {
    final q = _busqueda.text.trim().toLowerCase();
    if (q.length < 2) return const [];
    final res = _todos.where((a) {
      return a.nombre.toLowerCase().contains(q) ||
          a.matricula.toLowerCase().contains(q) ||
          a.correo.toLowerCase().contains(q);
    }).toList();
    res.sort((x, y) => x.nombre.compareTo(y.nombre));
    return res.take(12).toList();
  }

  /// Avisos que dependen del alumno y del tipo elegido. No bloquean: señalan.
  List<String> get _observaciones {
    final o = <String>[];
    final a = _elegido;
    if (a == null) return o;
    final est = a.estatus.toLowerCase();
    if (est.contains('baja')) {
      o.add('Este alumno está dado de baja. Revise si procede emitirle el documento.');
    }
    if (_tipo == 'noadeudo') {
      o.add('La carta de no adeudo afirma que está al corriente: confirme el '
          'estado de cuenta antes de emitirla.');
    }
    if ((_tipo == 'pasante' || _tipo == 'terminacion') && est.contains('activo')) {
      o.add('El alumno aparece como activo. Estas cartas son para quien ya '
          'concluyó las materias.');
    }
    if (_programa == null || _programa!.isEmpty) {
      o.add('Sin programa no se puede armar el documento: elíjalo abajo.');
    }
    if (_tipo == 'kardex' && (_generacion.text.trim().isEmpty)) {
      o.add('Sin generación, el kárdex no puede deducir el periodo de cada '
          'materia y saldrá con esa columna vacía.');
    }
    return o;
  }

  /// Vista previa: no consume folio ni queda registrada.
  Future<void> _previa() async {
    final mat = _matricula.text.trim();
    if (mat.isEmpty) {
      _aviso('Elija primero al alumno.');
      return;
    }
    setState(() => _previendo = true);
    try {
      final correo = await SessionStore.realEmail();
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'documento_preview_pdf',
        'tipo': _tipo,
        'matricula': mat,
        if ((_programa ?? '').isNotEmpty) 'programa': _programa!,
        'actor': correo ?? '',
      });
      if (!mounted) return;
      setState(() => _previendo = false);
      await launchUrl(uri, webOnlyWindowName: '_blank');
    } catch (e) {
      if (!mounted) return;
      setState(() => _previendo = false);
      _aviso('No se pudo abrir la vista previa: $e');
    }
  }

  Future<void> _generar() async {
    if (_matricula.text.trim().isEmpty) {
      _aviso('Elija al alumno o escriba su matrícula.');
      return;
    }
    if ((_programa ?? '').isEmpty) {
      _aviso('Falta el programa.');
      return;
    }
    final ok = await _confirmar();
    if (ok != true) return;
    setState(() {
      _generando = true;
      _folio = null;
      _urlPdf = null;
      _urlDocx = null;
    });
    try {
      final quien = await SessionStore.realEmail();
      final payload = <String, dynamic>{
        'accion': 'documento_generar',
        'tipo': _tipo,
        'matricula': _matricula.text.trim(),
        'nombre': _nombre.text.trim(),
        'programa': _programa ?? '',
        'modalidad': _modalidad ?? '',
        'generacion': _generacion.text.trim(),
        'semestreTexto': _semestre.text.trim(),
        'firmar': _firmar,
        'validadoPor': quien ?? 'Vicerrectoría Académica',
        if (_tipo == 'noadeudo') 'confirmarAdeudo': true,
      };
      final resp = await http
          .post(
            Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 150));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'No se pudo generar.');
      }
      if (!mounted) return;
      setState(() {
        _generando = false;
        _folio = data['folio'] as String?;
        _urlPdf = data['pdf'] as String?;
        _urlDocx = data['docx'] as String?;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _generando = false);
      _aviso('Error: $e');
    }
  }

  /// El folio es consecutivo y queda registrado: conviene confirmar, sobre
  /// todo porque emitir dos veces deja dos folios del mismo documento.
  Future<bool?> _confirmar() => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Emitir ${_tipoActual.nombre.toLowerCase()}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                  '${_nombre.text.trim()}\n${_matricula.text.trim()} · '
                  '${_programa ?? ''}',
                  style: const TextStyle(fontSize: 13)),
            ),
            const SizedBox(height: 10),
            Text(
                _firmar
                    ? 'Se emitirá FIRMADO, con folio consecutivo y registro en '
                        'Documentos emitidos. Al alumno no se le avisa.'
                    : 'Se emitirá SIN firma, con línea para rúbrica manual. '
                        'Lleva folio y queda registrado. Al alumno no se le avisa.',
                style: const TextStyle(fontSize: 12.5, height: 1.4)),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                style: FilledButton.styleFrom(backgroundColor: cessumRed),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Emitir')),
          ],
        ),
      );

  void _aviso(String m) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: Colors.redAccent,
      content: Text(m),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final programas = programasAcademicos.map((p) => p.nombre).toList();
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Documentos oficiales',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _selectorModo(),
          const SizedBox(height: 18),
          if (_modo == 'aspirante') ..._vistaAspirante(programas) else if (_modo == 'docente') ..._vistaDocente() else ...[
          _ayuda(),
          const SizedBox(height: 16),
          _buscadorAlumno(),
          const SizedBox(height: 16),
          _selectorTipo(),
          const SizedBox(height: 14),
          if (_observaciones.isNotEmpty) ...[
            _avisos(),
            const SizedBox(height: 14),
          ],
          _datos(programas),
          const SizedBox(height: 16),
          _acciones(),
          if (_folio != null) ...[
            const SizedBox(height: 20),
            _resultado(),
          ],
          ],
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  //  (5-oct-2026) MODO ASPIRANTE · CARTA DE ACEPTACIÓN
  //  Para quien ya fue admitido y todavía no tiene matrícula: la piden las
  //  financieras y el crédito educativo antes de que se inscriba.
  // ════════════════════════════════════════════════════════════════════
  final _aspNombre = TextEditingController();
  final _aspGen = TextEditingController();
  String? _aspPrograma;
  String _aspModalidad = 'No escolarizada';
  DateTime? _aspInicio;
  bool _aspEmitiendo = false;
  String _aspError = '';
  Map<String, dynamic>? _aspResultado;

  Future<void> _emitirAceptacion() async {
    final nombre = _aspNombre.text.trim();
    if (nombre.split(RegExp(r'\s+')).length < 2 || _aspPrograma == null || _aspGen.text.trim().isEmpty) {
      setState(() => _aspError = 'Escriba el nombre completo y elija el programa y la generación.');
      return;
    }
    setState(() { _aspEmitiendo = true; _aspError = ''; _aspResultado = null; });
    try {
      final actor = await SessionStore.realEmail() ?? '';
      final i = _aspInicio;
      final r = await http.post(Uri.parse(guardianUrl),
          headers: {'Content-Type': 'text/plain;charset=utf-8'},
          body: jsonEncode({
            'accion': 'carta_aceptacion', 'actor': actor, 'nombre': nombre, 'programa': _aspPrograma,
            'modalidad': _aspModalidad, 'generacion': _aspGen.text.trim(), 'firmar': _firmar,
            if (i != null) 'inicio': '${i.year}-${i.month.toString().padLeft(2, '0')}-${i.day.toString().padLeft(2, '0')}',
          })).timeout(const Duration(seconds: 90));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo emitir.');
      if (mounted) setState(() => _aspResultado = d);
    } catch (e) {
      if (mounted) setState(() => _aspError = '$e'.replaceFirst('Exception: ', ''));
    }
    if (mounted) setState(() => _aspEmitiendo = false);
  }

  List<Widget> _vistaAspirante(List<String> programas) => [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: cessumGold.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(12)),
          child: const Text(
            'Carta de aceptación para quien ya fue admitido y aún no tiene matrícula. La piden el crédito educativo y las financieras '
            'antes de la inscripción. Indica el programa, la generación y la semana de inicio, y que la inscripción queda sujeta a documentos y pago.',
            style: TextStyle(fontSize: 12.5, height: 1.45),
          ),
        ),
        const SizedBox(height: 14),
        TextField(controller: _aspNombre, textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Nombre completo del aspirante', border: OutlineInputBorder(), isDense: true)),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _aspPrograma,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Programa', border: OutlineInputBorder(), isDense: true),
          items: [for (final p in programas) DropdownMenuItem(value: p, child: Text(p, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _aspPrograma = v),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _aspModalidad,
              decoration: const InputDecoration(labelText: 'Modalidad', border: OutlineInputBorder(), isDense: true),
              items: const [
                DropdownMenuItem(value: 'No escolarizada', child: Text('No escolarizada')),
                DropdownMenuItem(value: 'Mixta', child: Text('Mixta')),
              ],
              onChanged: (v) => setState(() => _aspModalidad = v ?? 'No escolarizada'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(controller: _aspGen,
                decoration: const InputDecoration(labelText: 'Generación (p. ej. 27-1)', border: OutlineInputBorder(), isDense: true)),
          ),
        ]),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () async {
            final hoy = DateTime.now();
            final f = await showDatePicker(context: context, initialDate: _aspInicio ?? hoy, firstDate: hoy.subtract(const Duration(days: 30)), lastDate: hoy.add(const Duration(days: 400)));
            if (f != null) setState(() => _aspInicio = f);
          },
          icon: const Icon(Icons.event_outlined, size: 18),
          label: Text(_aspInicio == null
              ? 'Semana de inicio de clases (opcional)'
              : 'Inicio: semana del ${_aspInicio!.day.toString().padLeft(2, '0')}/${_aspInicio!.month.toString().padLeft(2, '0')}/${_aspInicio!.year}'),
        ),
        const SizedBox(height: 6),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _firmar,
          activeThumbColor: cessumRed,
          onChanged: (v) => setState(() => _firmar = v),
          title: const Text('Con firma del Rector', style: TextStyle(fontSize: 13.5)),
        ),
        if (_aspError.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_aspError, style: const TextStyle(color: cessumRed, fontSize: 12.5))),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: cessumRed, minimumSize: const Size(0, 46)),
          onPressed: _aspEmitiendo ? null : _emitirAceptacion,
          icon: _aspEmitiendo
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.description_outlined),
          label: Text(_aspEmitiendo ? 'Emitiendo…' : 'Emitir carta de aceptación'),
        ),
        if (_aspResultado != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFF1E8E3E).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Folio ${_aspResultado!['folio']}', style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('${_aspResultado!['nota'] ?? ''}', style: const TextStyle(fontSize: 12.5)),
              const SizedBox(height: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1E8E3E)),
                onPressed: () => launchUrl(Uri.parse('${_aspResultado!['pdfUrl']}'), webOnlyWindowName: '_blank'),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('Abrir el PDF'),
              ),
            ]),
          ),
        ],
      ];

  // ════════════════════════════════════════════════════════════════════
  //  MODO DOCENTE
  // ════════════════════════════════════════════════════════════════════

  Widget _selectorModo() => SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(
                value: 'alumno',
                label: Text('Alumnos'),
                icon: Icon(Icons.school_outlined, size: 18)),
            ButtonSegment(
                value: 'docente',
                label: Text('Docentes'),
                icon: Icon(Icons.badge_outlined, size: 18)),
            // (5-oct-2026) Carta de aceptación: el aspirante aún no tiene matrícula.
            ButtonSegment(
                value: 'aspirante',
                label: Text('Aspirantes'),
                icon: Icon(Icons.person_add_alt_outlined, size: 18)),
          ],
          selected: {_modo},
          showSelectedIcon: false,
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((st) =>
                st.contains(WidgetState.selected)
                    ? cessumRed.withValues(alpha: 0.12)
                    : null),
            foregroundColor: WidgetStateProperty.resolveWith((st) =>
                st.contains(WidgetState.selected) ? cessumRed : null),
          ),
          onSelectionChanged: (v) {
            setState(() => _modo = v.first);
            if (_modo == 'docente' && !_docentesCargados) _cargarDocentes();
          },
        ),
      );

  Future<void> _cargarDocentes() async {
    setState(() => _cargandoDocentes = true);
    try {
      final r = await http
          .get(Uri.parse('$guardianUrl?accion=docentes_lista'))
          .timeout(const Duration(seconds: 40));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      final lista = ((d['docentes'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .where((x) => (x['correo'] ?? '').toString().contains('@'))
          .toList()
        ..sort((a, b) => (a['nombre'] ?? '')
            .toString()
            .compareTo((b['nombre'] ?? '').toString()));
      if (!mounted) return;
      setState(() {
        _docentes = lista;
        _cargandoDocentes = false;
        _docentesCargados = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargandoDocentes = false;
        _errorDoc = 'No se pudo cargar la lista de docentes.';
      });
    }
  }

  Future<void> _elegirDocente(Map<String, dynamic> d) async {
    setState(() {
      _docenteSel = d;
      _materiasDoc = [];
      _materiaSel = null;
      _folioDoc = null;
      _pdfDoc = null;
      _errorDoc = null;
      _avisoMaterias = null;
      _cargandoMaterias = true;
    });
    try {
      final r = await http
          .get(Uri.parse('$guardianUrl?accion=constancias_listar'
              '&correo=${Uri.encodeComponent((d['correo'] ?? '').toString())}'))
          .timeout(const Duration(seconds: 60));
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      final lista = ((data['constancias'] ?? data['materias'] ?? data['lista'])
                  as List? ??
              [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        _materiasDoc = lista;
        _cargandoMaterias = false;
        if (data['ok'] != true) {
          _avisoMaterias = (data['error'] ?? 'No se pudo consultar.').toString();
        } else if (lista.isEmpty) {
          _avisoMaterias =
              'Este docente no tiene materias con acta validada. La constancia '
              'de trabajo solo se emite de materias ya concluidas y con acta '
              'validada, porque acredita un servicio que ya se prestó.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargandoMaterias = false;
        _avisoMaterias = 'No se pudieron consultar sus materias.';
      });
    }
  }

  Future<void> _generarConstanciaTrabajo() async {
    final d = _docenteSel, m = _materiaSel;
    if (d == null || m == null) return;
    setState(() {
      _generandoDoc = true;
      _errorDoc = null;
      _folioDoc = null;
      _pdfDoc = null;
    });
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'constancia_generar',
        'correo': (d['correo'] ?? '').toString(),
        'programa': (m['programa'] ?? '').toString(),
        'generacion': (m['generacionTxt'] ?? m['generacion'] ?? '').toString(),
        'grupo': (m['grupo'] ?? '').toString(),
        'materia': (m['materia'] ?? '').toString(),
      });
      final r = await http.get(uri).timeout(const Duration(seconds: 120));
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        setState(() {
          _folioDoc = (data['folio'] ?? '').toString();
          _pdfDoc = (data['pdfUrl'] ?? '').toString();
          _generandoDoc = false;
        });
      } else {
        setState(() {
          _errorDoc = (data['error'] ?? 'No se pudo generar.').toString();
          _generandoDoc = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorDoc = 'El servidor tardó demasiado. Inténtalo de nuevo.';
        _generandoDoc = false;
      });
    }
  }

  String _isoFecha(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fechaCorta(DateTime? d) {
    if (d == null) return 'Elegir fecha';
    const m = ['ene', 'feb', 'mar', 'abr', 'may', 'jun',
               'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  Future<void> _elegirFecha(bool inicio) async {
    final base = (inicio ? _mInicio : _mTermino) ??
        (inicio ? DateTime(DateTime.now().year - 1) : (_mInicio ?? DateTime.now()));
    final f = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2010),
      lastDate: DateTime.now().add(const Duration(days: 366)),
      helpText: inicio ? 'Fecha de inicio' : 'Fecha de término',
    );
    if (f == null || !mounted) return;
    setState(() {
      if (inicio) {
        _mInicio = f;
      } else {
        _mTermino = f;
      }
    });
  }

  /// Horas sugeridas con la misma regla que usa el Guardián para las
  /// constancias del sistema. Es solo sugerencia: la materia antigua pudo
  /// tener otra carga, y el campo queda editable.
  String _horasSugeridas() {
    final pr = (_mPrograma == '__otro__' ? _mProgramaOtro.text : (_mPrograma ?? ''))
        .toLowerCase()
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o');
    if (pr.trim() == 'maestria en educacion') return '10';
    if (_mModalidad == 'Mixta') return '15';
    return '5';
  }

  Future<void> _generarManual() async {
    final programa = _mPrograma == '__otro__'
        ? _mProgramaOtro.text.trim()
        : (_mPrograma ?? '');
    final faltan = <String>[];
    if (_mDocente.text.trim().isEmpty) faltan.add('docente');
    if (_mMateria.text.trim().isEmpty) faltan.add('materia');
    if (programa.isEmpty) faltan.add('programa');
    if (_mInicio == null) faltan.add('fecha de inicio');
    if (_mTermino == null) faltan.add('fecha de término');
    if ((int.tryParse(_mHoras.text.trim()) ?? 0) <= 0) faltan.add('horas');
    if (faltan.isNotEmpty) {
      setState(() => _errorDoc = 'Faltan datos: ${faltan.join(', ')}.');
      return;
    }
    if (_mTermino!.isBefore(_mInicio!)) {
      setState(() => _errorDoc = 'La fecha de término es anterior a la de inicio.');
      return;
    }
    setState(() {
      _generandoDoc = true;
      _errorDoc = null;
      _folioDoc = null;
      _pdfDoc = null;
    });
    try {
      final q = <String, String>{
        'accion': 'constancia_generar',
        'manual': '1',
        'docente': _mDocente.text.trim(),
        'materia': _mMateria.text.trim(),
        'programa': programa,
        'modalidad': _mModalidad,
        'inicio': _isoFecha(_mInicio!),
        'termino': _isoFecha(_mTermino!),
        'horas': _mHoras.text.trim(),
      };
      if (_mArticulo != 'auto') q['articulo'] = _mArticulo;
      final uri = Uri.parse(guardianUrl).replace(queryParameters: q);
      final r = await http.get(uri).timeout(const Duration(seconds: 120));
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _generandoDoc = false;
        if (data['ok'] == true) {
          _folioDoc = (data['folio'] ?? '').toString();
          _pdfDoc = (data['pdfUrl'] ?? '').toString();
        } else {
          _errorDoc = (data['error'] ?? 'No se pudo generar.').toString();
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _generandoDoc = false;
        _errorDoc = 'El servidor tardó demasiado. Inténtalo de nuevo.';
      });
    }
  }

  List<Widget> _formManual() {
    final programas = programasAcademicos.map((p) => p.nombre).toList();
    InputDecoration dec(String l, {String? ayuda}) => InputDecoration(
          labelText: l,
          helperText: ayuda,
          helperMaxLines: 2,
          isDense: true,
          border: const OutlineInputBorder(),
        );
    return [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cessumRed.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cessumRed.withValues(alpha: 0.2)),
        ),
        child: Text(
          'Para materias impartidas antes de la plataforma. Los datos se '
          'teclean y la constancia sale con el mismo formato, firma y folio; '
          'queda registrada como captura manual. Verifica los datos contra el '
          'expediente: lo que escribas aquí es lo que se certifica.',
          style: TextStyle(fontSize: 12, height: 1.5, color: cessumInk(context)),
        ),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _mDocente,
        decoration: dec('Docente, con grado',
            ayuda: 'Ej. Dra. María López Ruiz. El grado se usa para el «el/la».'),
      ),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        value: _mArticulo,
        decoration: dec('Tratamiento en el texto'),
        items: const [
          DropdownMenuItem(value: 'auto', child: Text('Según el grado (automático)')),
          DropdownMenuItem(value: 'el', child: Text('el C. …')),
          DropdownMenuItem(value: 'la', child: Text('la C. …')),
        ],
        onChanged: (v) => setState(() => _mArticulo = v ?? 'auto'),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: _mMateria,
        decoration: dec('Asignatura impartida'),
      ),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        value: _mPrograma,
        isExpanded: true,
        decoration: dec('Programa'),
        items: [
          ...programas.map((p) => DropdownMenuItem(value: p, child: Text(p))),
          const DropdownMenuItem(
              value: '__otro__', child: Text('Otro (escribirlo)')),
        ],
        onChanged: (v) => setState(() => _mPrograma = v),
      ),
      if (_mPrograma == '__otro__') ...[
        const SizedBox(height: 10),
        TextField(
          controller: _mProgramaOtro,
          decoration: dec('Nombre del programa',
              ayuda: 'Tal como debe aparecer en la constancia.'),
          onChanged: (_) => setState(() {}),
        ),
      ],
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        value: _mModalidad,
        decoration: dec('Modalidad'),
        items: const [
          DropdownMenuItem(value: 'No escolarizada', child: Text('No escolarizada')),
          DropdownMenuItem(value: 'Mixta', child: Text('Mixta')),
          DropdownMenuItem(value: 'Escolarizada', child: Text('Escolarizada')),
        ],
        onChanged: (v) => setState(() => _mModalidad = v ?? 'No escolarizada'),
      ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _elegirFecha(true),
            icon: const Icon(Icons.event, size: 17),
            label: Text('Inicio: ${_fechaCorta(_mInicio)}',
                style: const TextStyle(fontSize: 12.5)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _elegirFecha(false),
            icon: const Icon(Icons.event_available, size: 17),
            label: Text('Término: ${_fechaCorta(_mTermino)}',
                style: const TextStyle(fontSize: 12.5)),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      TextField(
        controller: _mHoras,
        keyboardType: TextInputType.number,
        decoration: dec('Horas frente a grupo',
            ayuda: 'Sugerido para este programa y modalidad: ${_horasSugeridas()} h.'),
      ),
      const SizedBox(height: 16),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
              backgroundColor: cessumRed,
              padding: const EdgeInsets.symmetric(vertical: 14)),
          onPressed: _generandoDoc ? null : _generarManual,
          icon: _generandoDoc
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.picture_as_pdf_outlined, size: 19),
          label: Text(_generandoDoc
              ? 'Generando constancia…'
              : 'Generar constancia de trabajo'),
        ),
      ),
    ];
  }

  List<Widget> _vistaDocente() {
    final q = _buscaDoc.text.trim().toLowerCase();
    final visibles = q.isEmpty
        ? _docentes
        : _docentes.where((d) {
            final t = '${d['nombre']} ${d['correo']}'.toLowerCase();
            return q.split(RegExp(r'\s+')).every((w) => t.contains(w));
          }).toList();

    return [
      Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: cessumGold.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          'Constancia de trabajo: acredita que el docente impartió una '
          'asignatura, con sus horas, modalidad y periodo. Se emite una por '
          'materia, solo de las ya concluidas con acta validada. Los datos '
          'salen de la asignación; no hay que teclear nada.',
          style: TextStyle(fontSize: 12.5, height: 1.5, color: cessumInk(context)),
        ),
      ),
      const SizedBox(height: 14),
      SizedBox(
        width: double.infinity,
        child: SegmentedButton<String>(
          segments: const [
            ButtonSegment(
                value: 'sistema',
                label: Text('Materia de la plataforma'),
                icon: Icon(Icons.cloud_done_outlined, size: 17)),
            ButtonSegment(
                value: 'manual',
                label: Text('Captura manual'),
                icon: Icon(Icons.edit_note, size: 18)),
          ],
          selected: {_fuenteDoc},
          showSelectedIcon: false,
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((st) =>
                st.contains(WidgetState.selected)
                    ? cessumGold.withValues(alpha: 0.16)
                    : null),
          ),
          onSelectionChanged: (v) => setState(() {
            _fuenteDoc = v.first;
            _folioDoc = null;
            _pdfDoc = null;
            _errorDoc = null;
            // Si ya había un docente elegido, se lleva a la captura manual.
            if (_fuenteDoc == 'manual' &&
                _docenteSel != null &&
                _mDocente.text.trim().isEmpty) {
              _mDocente.text =
                  '${_docenteSel!['titulo'] ?? ''} ${_docenteSel!['nombre'] ?? ''}'
                      .trim();
            }
          }),
        ),
      ),
      const SizedBox(height: 16),
      if (_fuenteDoc == 'manual') ..._formManual() else ...[

      // 1 · Docente
      Text('1 · Docente',
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w800, color: cessumInk(context))),
      const SizedBox(height: 8),
      if (_docenteSel != null)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cessumRed.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cessumRed.withValues(alpha: 0.35)),
          ),
          child: Row(children: [
            const Icon(Icons.badge_outlined, color: cessumRed, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${_docenteSel!['titulo'] ?? ''} ${_docenteSel!['nombre']}'.trim(),
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                Text('${_docenteSel!['correo']}',
                    style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
              ]),
            ),
            TextButton(
              onPressed: () => setState(() {
                _docenteSel = null;
                _materiasDoc = [];
                _materiaSel = null;
                _folioDoc = null;
                _pdfDoc = null;
                _errorDoc = null;
                _avisoMaterias = null;
              }),
              child: const Text('Cambiar'),
            ),
          ]),
        )
      else ...[
        TextField(
          controller: _buscaDoc,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search, size: 19),
            hintText: 'Buscar docente por nombre o correo',
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            suffixIcon: _buscaDoc.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _buscaDoc.clear()),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        if (_cargandoDocentes)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator(color: cessumRed)),
          )
        else
          Container(
            constraints: const BoxConstraints(maxHeight: 280),
            decoration: BoxDecoration(
              border: Border.all(color: cessumMuted(context).withValues(alpha: 0.2)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: visibles.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Sin coincidencias.',
                        style: TextStyle(color: cessumMuted(context))),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: visibles.length,
                    separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: cessumMuted(context).withValues(alpha: 0.12)),
                    itemBuilder: (_, i) {
                      final d = visibles[i];
                      return ListTile(
                        dense: true,
                        onTap: () => _elegirDocente(d),
                        title: Text('${d['titulo'] ?? ''} ${d['nombre']}'.trim(),
                            style: const TextStyle(fontSize: 13.5)),
                        subtitle: Text('${d['correo']}',
                            style: TextStyle(
                                fontSize: 11.5, color: cessumMuted(context))),
                        trailing: const Icon(Icons.chevron_right, size: 18),
                      );
                    },
                  ),
          ),
      ],

      // 2 · Materia
      if (_docenteSel != null) ...[
        const SizedBox(height: 20),
        Text('2 · Materia impartida',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: cessumInk(context))),
        const SizedBox(height: 8),
        if (_cargandoMaterias)
          const Padding(
            padding: EdgeInsets.all(18),
            child: Center(child: CircularProgressIndicator(color: cessumRed)),
          )
        else if (_avisoMaterias != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cessumGold.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(_avisoMaterias!,
                style: TextStyle(fontSize: 12.5, height: 1.5, color: cessumInk(context))),
          )
        else
          ..._materiasDoc.map((m) {
            final sel = identical(m, _materiaSel);
            return Container(
              margin: const EdgeInsets.only(bottom: 7),
              decoration: BoxDecoration(
                color: sel ? cessumRed.withValues(alpha: 0.07) : Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: sel
                        ? cessumRed.withValues(alpha: 0.45)
                        : cessumMuted(context).withValues(alpha: 0.18)),
              ),
              child: ListTile(
                dense: true,
                onTap: () => setState(() {
                  _materiaSel = m;
                  _folioDoc = null;
                  _pdfDoc = null;
                  _errorDoc = null;
                }),
                title: Text('${m['materia']}',
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                subtitle: Text(
                    '${m['programa']} · ${m['generacionTxt'] ?? m['generacion']} · '
                    'Grupo ${m['grupo']}',
                    style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
                trailing: Icon(sel ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 20, color: sel ? cessumRed : cessumMuted(context)),
              ),
            );
          }),
      ],

      // 3 · Generar
      if (_materiaSel != null) ...[
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: cessumRed,
                padding: const EdgeInsets.symmetric(vertical: 14)),
            onPressed: _generandoDoc ? null : _generarConstanciaTrabajo,
            icon: _generandoDoc
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.picture_as_pdf_outlined, size: 19),
            label: Text(_generandoDoc
                ? 'Generando constancia…'
                : 'Generar constancia de trabajo'),
          ),
        ),
      ],

      ],

      if (_errorDoc != null) ...[
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cessumRed.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(_errorDoc!,
              style: const TextStyle(fontSize: 12.5, color: cessumRed)),
        ),
      ],

      if (_folioDoc != null) ...[
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF6EC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF1E8E3E)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.check_circle, color: Color(0xFF1E8E3E), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Emitida · folio $_folioDoc',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ),
            ]),
            const SizedBox(height: 4),
            const Text(
                'Quedó registrada con folio. El docente no ha recibido ningún aviso.',
                style: TextStyle(fontSize: 11.5)),
            if ((_pdfDoc ?? '').isNotEmpty) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: cessumRed),
                onPressed: () => launchUrl(Uri.parse(_pdfDoc!), webOnlyWindowName: '_blank'),
                icon: const Icon(Icons.picture_as_pdf, size: 17),
                label: const Text('Descargar PDF'),
              ),
            ],
          ]),
        ),
      ],
      const SizedBox(height: 24),
    ];
  }

  Widget _ayuda() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cessumGold.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cessumGold.withValues(alpha: 0.3)),
        ),
        child: const Text(
          'Busque al alumno, elija el documento y véalo con «Vista previa» '
          'antes de emitirlo: la vista previa no consume folio ni queda '
          'registrada. «Emitir» sí genera folio consecutivo y lo deja en '
          '"Documentos emitidos". El documento no se le manda al alumno.',
          style: TextStyle(fontSize: 12, height: 1.45),
        ),
      );

  Widget _buscadorAlumno() {
    final hits = _coincidencias;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextField(
        controller: _busqueda,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: 'Buscar alumno por nombre, matrícula o correo',
          hintText: _cargandoAlumnos
              ? 'Cargando el padrón…'
              : 'Escriba al menos dos letras',
          prefixIcon: const Icon(Icons.search),
          border: const OutlineInputBorder(),
          filled: true,
          suffixIcon: _busqueda.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() => _busqueda.clear()),
                ),
        ),
      ),
      if (hits.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(top: 6),
          constraints: const BoxConstraints(maxHeight: 260),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: hits.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final a = hits[i];
              final baja = a.estatus.toLowerCase().contains('baja');
              return ListTile(
                dense: true,
                title: Text(a.nombre, style: const TextStyle(fontSize: 13.5)),
                subtitle: Text(
                    '${a.matricula} · ${a.programa}'
                    '${a.generacion.isEmpty ? '' : ' · ${a.generacion}'}',
                    style: const TextStyle(fontSize: 11.5)),
                trailing: baja
                    ? const Text('baja',
                        style: TextStyle(fontSize: 11, color: Colors.redAccent))
                    : null,
                onTap: () => _tomar(a),
              );
            },
          ),
        ),
      if (_elegido != null)
        Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: cessumGold.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            const Icon(Icons.person_outline, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  '${_elegido!.nombre} · ${_elegido!.matricula}'
                  '${_elegido!.estatus.isEmpty ? '' : ' · ${_elegido!.estatus}'}',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
            TextButton(
              onPressed: () => setState(() {
                _elegido = null;
                for (final c in [_matricula, _nombre, _generacion]) {
                  c.clear();
                }
                _programa = null;
                _modalidad = null;
              }),
              child: const Text('Cambiar', style: TextStyle(fontSize: 12)),
            ),
          ]),
        ),
    ]);
  }

  Widget _selectorTipo() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            value: _tipo,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Tipo de documento',
              border: OutlineInputBorder(),
              filled: true,
            ),
            items: _tiposDoc
                .map((t) => DropdownMenuItem(
                      value: t.clave,
                      child: Row(children: [
                        Icon(t.icono, size: 17, color: cessumGold),
                        const SizedBox(width: 8),
                        Flexible(
                            child: Text(t.nombre,
                                overflow: TextOverflow.ellipsis)),
                      ]),
                    ))
                .toList(),
            onChanged: (v) => setState(() {
              _tipo = v ?? _tipo;
              _folio = null;
              _urlPdf = null;
              _urlDocx = null;
            }),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(_tipoActual.pista,
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700)),
          ),
        ],
      );

  Widget _avisos() => Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF6E5),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: const Color(0xFFE7C98A)),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _observaciones
                .map((o) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline,
                                size: 15, color: Color(0xFFA56B16)),
                            const SizedBox(width: 7),
                            Expanded(
                                child: Text(o,
                                    style: const TextStyle(
                                        fontSize: 12, height: 1.35))),
                          ]),
                    ))
                .toList()),
      );

  Widget _datos(List<String> programas) => Column(children: [
        Row(children: [
          Expanded(
            child: TextField(
              controller: _matricula,
              decoration: const InputDecoration(
                labelText: 'Matrícula',
                border: OutlineInputBorder(),
                filled: true,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _generacion,
              decoration: const InputDecoration(
                labelText: 'Generación',
                hintText: '24-2',
                border: OutlineInputBorder(),
                filled: true,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _nombre,
          decoration: const InputDecoration(
            labelText: 'Nombre del alumno',
            border: OutlineInputBorder(),
            filled: true,
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: programas.contains(_programa) ? _programa : null,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Programa',
            border: OutlineInputBorder(),
            filled: true,
          ),
          items: programas
              .map((p) => DropdownMenuItem(
                  value: p, child: Text(p, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: (v) => setState(() => _programa = v),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: modalidadesEstudio.contains(_modalidad) ? _modalidad : null,
          decoration: const InputDecoration(
            labelText: 'Modalidad',
            border: OutlineInputBorder(),
            filled: true,
          ),
          items: modalidadesEstudio
              .map((m) => DropdownMenuItem(value: m, child: Text(m)))
              .toList(),
          onChanged: (v) => setState(() => _modalidad = v),
        ),
        if (_tipo == 'constancia' || _tipo == 'inscripcion') ...[
          const SizedBox(height: 12),
          TextField(
            controller: _semestre,
            decoration: const InputDecoration(
              labelText: 'Semestre o ciclo (texto que aparecerá)',
              hintText: 'Cuarto semestre',
              border: OutlineInputBorder(),
              filled: true,
            ),
          ),
        ],
        const SizedBox(height: 6),
        SwitchListTile(
          value: _firmar,
          onChanged: (v) => setState(() => _firmar = v),
          activeColor: cessumRed,
          contentPadding: EdgeInsets.zero,
          title: const Text('Validar y firmar', style: TextStyle(fontSize: 14)),
          subtitle: const Text(
              'Apagado: sale con línea para rúbrica manual.',
              style: TextStyle(fontSize: 11.5)),
        ),
      ]);

  Widget _acciones() => Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: (_previendo || _generando) ? null : _previa,
            icon: _previendo
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.visibility_outlined, size: 18),
            label: Text(_previendo ? 'Abriendo…' : 'Vista previa'),
            style: OutlinedButton.styleFrom(
              foregroundColor: cessumRed,
              side: const BorderSide(color: cessumRed),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            onPressed: (_generando || _previendo) ? null : _generar,
            icon: _generando
                ? const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.verified_outlined, size: 18),
            label: Text(_generando ? 'Generando…' : 'Emitir con folio'),
            style: FilledButton.styleFrom(
              backgroundColor: cessumRed,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ]);

  Widget _resultado() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF6EC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF1E8E3E)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.check_circle, color: Color(0xFF1E8E3E), size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Emitido · folio $_folio',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 4),
          const Text(
              'Quedó registrado en «Documentos emitidos». El alumno no ha '
              'recibido ningún aviso.',
              style: TextStyle(fontSize: 11.5)),
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 8, children: [
            if (_urlPdf != null)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: cessumRed),
                onPressed: () =>
                    launchUrl(Uri.parse(_urlPdf!), webOnlyWindowName: '_blank'),
                icon: const Icon(Icons.picture_as_pdf, size: 17),
                label: const Text('Descargar PDF'),
              ),
            if (_urlDocx != null)
              OutlinedButton.icon(
                onPressed: () =>
                    launchUrl(Uri.parse(_urlDocx!), webOnlyWindowName: '_blank'),
                icon: const Icon(Icons.description_outlined, size: 17),
                label: const Text('Descargar Word'),
              ),
          ]),
        ]),
      );
}
