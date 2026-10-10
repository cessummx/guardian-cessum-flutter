// =====================================================================
//  planeacion_didactica_screen.dart · CESSUM · Aula CESSUM
//  PLANEACIÓN DIDÁCTICA CON IA · modelo SESUM
//
//  Produce la planeación completa de una asignatura: datos curriculares,
//  fines de aprendizaje, dosificación de las sesiones, y cada sesión en
//  INICIO · DESARROLLO · CIERRE desde el marco interconductual.
//
//  LA PANTALLA PREVIA ES DIRECTIVA, no un formulario en blanco. Antes de
//  preguntar nada, el sistema muestra el ANÁLISIS FUNCIONAL del propósito
//  oficial —qué nivel de interacción piden los fines de aprendizaje de esa
//  asignatura— y cada pregunta llega con una opción ya recomendada y el
//  porqué. Si el docente elige algo que no cuadra con lo que su propio
//  programa pide, la pantalla se lo dice ahí mismo.
//
//  Lo que NO se pregunta porque el sistema ya lo sabe: denominación y
//  clave oficiales, fines de aprendizaje, temario, semestre, créditos,
//  modalidad y —lo más importante— cuántas sesiones tiene el curso.
// =====================================================================
import 'dart:async';
import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;   // (4-oct-2026) adjuntar la literatura del docente (PDF, Word, texto)
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'biblioteca_screen.dart';   // (5-oct-2026) biblioteca de bloques
import 'auth/session_store.dart';
import 'planeacion_documento.dart';
import 'generador_diapositivas_screen.dart';

class PlaneacionDidacticaScreen extends StatefulWidget {
  final Map<String, dynamic>? grupoInicial;
  /// (5-oct-2026) Desde «Mis planeaciones»: abrir directo una planeación ya hecha y dejar escrita la corrección.
  final String? abrirId;
  final String? abrirMateria;
  final String? abrirGrupo;
  final String? retroInicial;
  const PlaneacionDidacticaScreen({super.key, this.grupoInicial, this.abrirId, this.abrirMateria, this.abrirGrupo, this.retroInicial});
  @override
  State<PlaneacionDidacticaScreen> createState() => _PlaneacionDidacticaScreenState();
}

class _PlaneacionDidacticaScreenState extends State<PlaneacionDidacticaScreen> {
  // 0 materia · 1 ELEGIR RUTA · 2 encuadre y preguntas · 3 planeación
  int _paso = 0;
  List<Map<String, dynamic>> _entregas = [];
  bool _entregando = false;
  String _avisoEntrega = '';
  bool _avisoEntregaOk = false;
  bool _cargando = true;
  bool _ocupado = false;
  String _error = '';
  String _correo = '';
  // (9-oct-2026) true cuando ninguna fuente trajo el correo: se muestra qué hacer y no se llama al Guardián.
  bool _sinCorreo = false;
  List<Map<String, dynamic>> _grupos = [];
  // (5-oct-2026) Planeaciones ya generadas, para volver a ellas (contraste con la clase real y ajustes).
  List<Map<String, dynamic>> _misPlanes = [];
  Map<String, dynamic>? _grupo;

  // (9-sep) BUSCADOR Y FILTROS DE LA LISTA DE MATERIAS.
  // Con siete u ocho asignaturas en pantalla, varias ya cerradas, encontrar
  // la que se va a planear era leer toda la lista. El buscador mira materia,
  // programa, generación y grupo a la vez, así que «26-1» o «sabatino»
  // sirven igual que el nombre de la asignatura.
  final TextEditingController _buscar = TextEditingController();
  // 'vigentes' | 'terminadas' | 'todas'. Arranca en 'vigentes' porque lo
  // normal es planear lo que está corriendo; el chip dice cuántas hay del
  // otro lado, para que nadie crea que se le perdieron.
  String _filtro = 'vigentes';

  Map<String, dynamic>? _ctx;
  List<Map<String, dynamic>> _preguntas = [];
  // (4-oct-2026) La literatura del docente para esta materia (fichas hechas por la IA).
  List<Map<String, dynamic>> _lit = [];
  int _litMax = 12;
  int _litLibros = 5, _litPaginas = 50;   // (5-oct-2026) máximo de libros por materia y de páginas por libro
  bool _litOcupado = false;
  String _litEstado = '';
  final Map<String, dynamic> _resp = {};
  final Map<String, TextEditingController> _libres = {};

  String _id = '';
  String _docente = '';
  String _modeloVersion = '';
  Map<String, dynamic>? _plan;
  int _version = 0, _quedan = 3;
  bool _verificandoBib = false;   // (5-oct-2026) bibliografía verificada
  List<Map<String, dynamic>> _ajustes = [];   // (5-oct-2026) ajustes aprendidos de la clase real
  List<Map<String, dynamic>> _prefs = [];     // (5-oct-2026) reglas aprendidas de las versiones que el docente ajustó
  bool _aprendiendo = false;
  List<Map<String, dynamic>> _avisos = [];
  Map<String, dynamic>? _metricas;
  final _retro = TextEditingController();

  // (28-sep) Avance de la generación por pasos.
  int _progTotal = 0;
  int _progVersion = 1;
  final List<int> _progHechas = [];
  List<int> _progPorHacer = [];
  int _progActual = 0;
  String _progRetro = '';
  String _progNota = '';
  bool _progDetenido = false;
  Map<String, dynamic>? _pendiente;

  @override
  void initState() {
    super.initState();
    _grupo = widget.grupoInicial;
    _cargar();
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body, {int seg = 60}) async {
    // (9-oct-2026) Si el correo no estaba al cargar (la sesión se restauró después), se vuelve a buscar antes de pedir nada.
    if (_correo.isEmpty) _correo = await _resolverCorreo();
    final r = await http
        .post(Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode({...body, 'correo': _correo, 'actor': _correo}))
        .timeout(Duration(seconds: seg));
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (j['ok'] != true && '${j['error'] ?? ''}'.contains('Falta el correo')) {
      // El Guardián solo dice que falta; aquí se dice qué hacer.
      j['error'] = _correo.isEmpty
          ? 'No pude identificar tu correo: la sesión de la app no lo tiene. Cierra sesión, vuelve a entrar y abre de nuevo esta pantalla.'
          : 'El Guardián no reconoció el correo $_correo. Cierra sesión y vuelve a entrar; si sigue igual, avisa a Vicerrectoría.';
    }
    return j;
  }

  /* (9-oct-2026) DE DÓNDE SALE EL CORREO DEL DOCENTE.
     Antes solo se leía SessionStore.validEmail(); si venía vacío (sesión local caducada, o «Ver como profesor» con
     una cuenta sin correo), cada ruta del Guardián contestaba «Falta el correo del docente.» sin decir por qué, y
     desde el Laboratorio de clases —que abre esta pantalla con la materia ya elegida— el docente se topaba con el
     aviso en el primer botón. Ahora se busca en orden:
       1. lo que traiga quien abre la pantalla en grupoInicial: correo | correoDocente | docenteCorreo | email;
       2. la sesión de la app (en «Ver como profesor», el correo del profesor);
       3. el correo real con el que se entró (por si la cuenta suplantada no trae correo).
     Si nada trae un correo, la pantalla lo dice en claro y no llama al Guardián. */
  Future<String> _resolverCorreo() async {
    String limpio(dynamic v) => '${v ?? ''}'.trim().toLowerCase();
    final g = widget.grupoInicial;
    if (g != null) {
      for (final k in const ['correo', 'correoDocente', 'docenteCorreo', 'email']) {
        final v = limpio(g[k]);
        if (v.contains('@')) return v;
      }
    }
    try {
      final v = limpio(await SessionStore.validEmail());
      if (v.contains('@')) return v;
    } catch (_) {}
    try {
      final v = limpio(await SessionStore.realEmail());
      if (v.contains('@')) return v;
    } catch (_) {}
    return '';
  }

  /* (9-sep) GENERAR UNA PLANEACIÓN TARDA, Y ESO NO ES UNA FALLA.
     El tope estaba en 240 segundos y la planeación de la Maestría en
     Educación son SIETE sesiones, cada una con su encuadre, sus actividades
     y su evaluación. Pasado el tope salía «TimeoutException after
     0:04:00.000000: Future not completed», que no le dice nada al docente y
     lo peor: la planeación SÍ se estaba generando del otro lado, así que
     abandonaba algo que ya casi estaba.
     Ahora se espera lo que haga falta —quince minutos de tope duro, solo
     para no dejar la pantalla colgada para siempre— y mientras tanto se
     muestra en qué va, con el tiempo corriendo. */
  Timer? _reloj;
  int _segundos = 0;
  String _fase = '';

  void _empezarEspera(String fase) {
    _fase = fase;
    _segundos = 0;
    _reloj?.cancel();
    _reloj = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _segundos++);
    });
  }

  void _terminarEspera() {
    _reloj?.cancel();
    _reloj = null;
    if (mounted) setState(() { _segundos = 0; _fase = ''; });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    super.dispose();
  }

  /* La barra no finge saber cuánto falta: avanza con el tiempo hacia un
     techo del 95 % y ahí se queda hasta que llega la respuesta. Fingir un
     100 % que no ha ocurrido es peor que no tener barra. */
  Widget _barraEspera() {
    if (_progTotal > 0 || (_ocupado && _progNota.isNotEmpty)) return _barraProgreso();
    if (_fase.isEmpty) return const SizedBox.shrink();
    final esperado = _fase == 'planeación' ? 420.0 : 180.0;
    final v = (_segundos / esperado).clamp(0.0, 0.95);
    final m = _segundos ~/ 60, sg = _segundos % 60;
    String dice;
    if (_segundos < 20) {
      dice = 'Leyendo la carta descriptiva y tus respuestas…';
    } else if (_segundos < 90) {
      dice = 'Armando el encuadre y la dosificación…';
    } else if (_segundos < 240) {
      dice = 'Escribiendo cada sesión: apertura, actividades y cierre…';
    } else if (_segundos < 420) {
      dice = 'Terminando la evaluación y las referencias…';
    } else {
      dice = 'Va larga, pero sigue trabajando. No cierres esta pantalla.';
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F1E8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7C98A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('Generando tu $_fase',
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
            ),
            Text('${m > 0 ? '$m min ' : ''}$sg s',
                style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: v,
              minHeight: 8,
              backgroundColor: cessumGold.withValues(alpha: 0.18),
              valueColor: const AlwaysStoppedAnimation(cessumRed),
            ),
          ),
          const SizedBox(height: 8),
          Text(dice, style: TextStyle(fontSize: 12.5, color: cessumMuted(context), height: 1.35)),
          const SizedBox(height: 4),
          Text('Puede tardar varios minutos. Si cierras la pantalla se pierde el trabajo.',
              style: TextStyle(fontSize: 11.5, color: cessumFaint(context))),
        ],
      ),
    );
  }

  /* (28-sep) El avance real: cuántas sesiones van y cuál se escribe. */
  Widget _barraProgreso() {
    final meta = _progPorHacer.length;
    final hechas = _progPorHacer.where(_progHechas.contains).length;
    final v = meta == 0 ? null : (hechas / meta).clamp(0.0, 1.0).toDouble();
    final m = _segundos ~/ 60, sg = _segundos % 60;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumGold.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
                _progTotal == 0
                    ? 'Preparando la planeación'
                    : _progVersion > 1
                        ? 'Versión $_progVersion · $hechas de $meta ${meta == 1 ? 'sesión' : 'sesiones'} con cambios'
                        : 'Planeación de $_progTotal sesiones · $hechas escritas',
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
          ),
          if (_ocupado)
            Text('${m > 0 ? '$m min ' : ''}$sg s',
                style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: v,
            minHeight: 8,
            backgroundColor: cessumGold.withValues(alpha: 0.18),
            valueColor: const AlwaysStoppedAnimation(cessumRed),
          ),
        ),
        if (_progTotal > 0) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 5, runSpacing: 5, children: [
            for (var n = 1; n <= _progTotal; n++) _chipSesionProg(n),
          ]),
        ],
        const SizedBox(height: 10),
        Text(_progNota, style: TextStyle(fontSize: 12.5, height: 1.35, color: cessumInk(context))),
        const SizedBox(height: 4),
        Text(
            _progDetenido
                ? 'Lo avanzado quedó guardado.'
                : 'Cada sesión se guarda al terminar. Si cierras la pantalla, al volver a esta materia podrás continuar donde se quedó.',
            style: TextStyle(fontSize: 11.5, color: cessumFaint(context))),
        if (_progDetenido && !_ocupado) ...[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () => _seguir(),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Continuar donde se quedó'),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _chipSesionProg(int n) {
    final aplica = _progPorHacer.contains(n);
    final hecha = _progHechas.contains(n);
    final actual = _ocupado && _progActual == n && !hecha;
    final Color c = !aplica
        ? cessumFaint(context)
        : hecha
            ? const Color(0xFF1E8E3E)
            : actual
                ? cessumGold
                : cessumMuted(context);
    return Container(
      width: 30,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: (hecha && aplica) ? c.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: actual ? 1.0 : 0.6), width: actual ? 2 : 1),
      ),
      child: Text('$n', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
    );
  }

  Widget _tarjetaPendiente() {
    final p = _pendiente!;
    final porHacer = _enteros(p['porHacer']).length;
    final faltan = _enteros(p['faltan']).length;
    final hechas = porHacer - faltan;
    final rev = p['revision'] == true;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cessumRed.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumRed.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.history, color: cessumRed, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                rev ? 'Tienes la versión ${p['version']} a medias' : 'Tienes una planeación a medias',
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
            'Iniciada el ${p['creado'] ?? ''}. '
            '${rev ? 'Van $hechas de $porHacer sesiones por reescribir' : 'Van $hechas de ${p['total']} sesiones escritas'}. '
            'Lo avanzado está guardado.',
            style: TextStyle(fontSize: 12.5, height: 1.35, color: cessumInk(context))),
        const SizedBox(height: 10),
        Row(children: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: _ocupado ? null : _reanudar,
            icon: const Icon(Icons.play_arrow, size: 18),
            label: const Text('Continuar'),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: _ocupado ? null : () => setState(() => _pendiente = null),
            child: const Text('Empezar una nueva'),
          ),
        ]),
      ]),
    );
  }

  Future<void> _cargar() async {
    try {
      _correo = await _resolverCorreo();
      if (_correo.isEmpty) {
        // Sin correo no hay nada que pedir: cada ruta del Guardián lo exige. Se explica y se ofrece reintentar.
        if (mounted) setState(() { _cargando = false; _sinCorreo = true; _error = ''; });
        return;
      }
      final g = await http
          .get(Uri.parse('$guardianUrl?accion=mis_grupos&correo=${Uri.encodeComponent(_correo)}'))
          .timeout(const Duration(seconds: 30));
      final gd = jsonDecode(g.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _grupos = ((gd['grupos'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _cargando = false;
        _sinCorreo = false;
        if (_grupo != null) _paso = 1;
      });
      _cargarEntregas();
      _cargarMisPlanes();
      _cargarPrefs();
      if ((widget.abrirId ?? '').isNotEmpty) {
        await _abrirPlaneacion({'id': widget.abrirId, 'materia': widget.abrirMateria ?? '', 'grupo': widget.abrirGrupo ?? ''});
        if (mounted && (widget.retroInicial ?? '').isNotEmpty) setState(() => _retro.text = widget.retroInicial!);
      }
    } catch (e) {
      if (mounted) setState(() { _cargando = false; _error = 'No se pudieron cargar tus materias: $e'; });
    }
  }

  /* (5-oct-2026) APRENDER DE LAS EDICIONES DEL DOCENTE. Sube su versión ajustada; la IA la compara con la generada y
     propone reglas para sus siguientes planeaciones. Él elige cuáles guardar y puede quitarlas. */
  Future<void> _cargarPrefs() async {
    try {
      final j = await _post({'accion': 'planea_preferencias'});
      if (j['ok'] == true && mounted) {
        setState(() => _prefs = ((j['preferencias'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList());
      }
    } catch (_) {}
  }

  Future<void> _quitarPref(Map<String, dynamic> p) async {
    try {
      final j = await _post({'accion': 'planea_preferencia_quitar', 'idPreferencia': '${p['id']}'});
      if (j['ok'] == true) await _cargarPrefs();
    } catch (_) {}
  }

  Future<void> _aprenderDeMiVersion() async {
    final input = html.FileUploadInputElement()..accept = '.pdf,.docx,.txt,.md,application/pdf';
    input.click();
    await input.onChange.first;
    final fs = input.files ?? const <html.File>[];
    if (fs.isEmpty) return;
    final f = fs.first;
    if (f.size > 20 * 1024 * 1024) {
      setState(() => _error = 'Tu archivo pasa de 20 MB.');
      return;
    }
    setState(() { _aprendiendo = true; _error = ''; });
    Map<String, dynamic> j;
    try {
      final bytes = await _bytesDeArchivo(f);
      j = await _post({'accion': 'planea_aprender', 'id': _id, 'nombre': f.name, 'mime': f.type, 'datos_b64': base64Encode(bytes)}, seg: 300);
    } catch (e) {
      j = {'ok': false, 'error': _msgError(e)};
    }
    if (!mounted) return;
    setState(() => _aprendiendo = false);
    if (j['ok'] != true) {
      setState(() => _error = '${j['error'] ?? 'No se pudo comparar tu versión.'}');
      return;
    }
    final reglas = ((j['reglas'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final difs = ((j['diferencias'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final elegidas = List<bool>.filled(reglas.length, true);
    final guardar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Lo que aprendí de tu versión'),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${j['resumen'] ?? ''}', style: const TextStyle(fontSize: 13.5, height: 1.5, fontWeight: FontWeight.w600)),
                if (difs.isNotEmpty)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('Qué cambiaste (${difs.length})', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    children: [
                      for (final d in difs)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text('${d['apartado']}: «${d['generado']}» → «${d['docente']}»', style: const TextStyle(fontSize: 12, height: 1.4)),
                        ),
                    ],
                  ),
                const SizedBox(height: 8),
                const Text('Reglas para tus siguientes planeaciones. Marca las que quieras guardar:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                for (var i = 0; i < reglas.length; i++)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: elegidas[i],
                    activeColor: cessumRed,
                    onChanged: (v) => setD(() => elegidas[i] = v ?? false),
                    title: Text('${reglas[i]['regla']}', style: const TextStyle(fontSize: 13)),
                    subtitle: Text('${reglas[i]['alcance'] == 'materia' ? 'Solo en esta materia' : 'En todas tus materias'} · ${reglas[i]['evidencia'] ?? ''}',
                        style: const TextStyle(fontSize: 11.5)),
                  ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No guardar nada')),
            FilledButton(
                style: FilledButton.styleFrom(backgroundColor: cessumRed),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Guardar las que elegí')),
          ],
        ),
      ),
    );
    if (guardar != true || !mounted) return;
    final sel = [for (var i = 0; i < reglas.length; i++) if (elegidas[i]) reglas[i]];
    if (sel.isEmpty) return;
    try {
      final g = await _post({'accion': 'planea_preferencias_guardar', 'reglas': sel, 'programa': '${j['programa'] ?? ''}',
        'materia': '${j['materia'] ?? ''}', 'idAprendizaje': '${j['idAprendizaje'] ?? ''}'});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${g['ok'] == true ? g['nota'] : g['error']}')));
      await _cargarPrefs();
    } catch (e) {
      if (mounted) setState(() => _error = _msgError(e));
    }
  }

  Widget _tarjetaPrefs() {
    final mat = _normTxt(_grupo?['materia']);
    final aplican = _prefs.where((p) => p['alcance'] != 'materia' || _normTxt(p['materia']) == mat).toList();
    if (aplican.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFF1E8E3E).withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1E8E3E).withValues(alpha: 0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Lo que aprendí de tus versiones (${aplican.length})', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text('Se aplican al generar esta planeación. Quita las que ya no quieras.', style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
        const SizedBox(height: 6),
        for (final p in aplican)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.only(top: 3), child: Icon(Icons.check, size: 15, color: Color(0xFF1E8E3E))),
            const SizedBox(width: 6),
            Expanded(child: Text('${p['regla']}${p['alcance'] == 'materia' ? ' (esta materia)' : ''}', style: const TextStyle(fontSize: 12.5, height: 1.4))),
            IconButton(tooltip: 'Quitar', visualDensity: VisualDensity.compact, iconSize: 18, onPressed: () => _quitarPref(p), icon: const Icon(Icons.close)),
          ]),
      ]),
    );
  }

  Future<void> _cargarMisPlanes() async {
    try {
      final j = await _post({'accion': 'planea_mis'});
      if (j['ok'] == true && mounted) {
        setState(() => _misPlanes = ((j['planeaciones'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .where((p) => ((p['versiones'] as num?) ?? 0) > 0)
            .toList());
      }
    } catch (_) {}
  }

  String _normTxt(Object? t) => '$t'.toLowerCase().trim();

  /// (5-oct-2026) Abre una planeación ya generada: para ver el contraste con la clase real, aceptar ajustes,
  /// descargarla o entregarla, sin volver a generarla.
  Future<void> _abrirPlaneacion(Map<String, dynamic> p) async {
    setState(() { _ocupado = true; _error = ''; });
    try {
      final j = await _post({'accion': 'planea_obtener', 'id': '${p['id']}'}, seg: 90);
      if (j['ok'] != true || j['planeacion'] == null) throw Exception(j['error'] ?? 'No se pudo abrir la planeación.');
      final g = _grupos.firstWhere(
          (x) => _normTxt(x['materia']) == _normTxt(p['materia']) && _normTxt(x['grupo']) == _normTxt(p['grupo']),
          orElse: () => _grupos.firstWhere((x) => _normTxt(x['materia']) == _normTxt(p['materia']),
              orElse: () => {'materia': p['materia'], 'grupo': p['grupo'], 'programa': '', 'generacion': ''}));
      if (!mounted) return;
      final vers = int.tryParse('${j['versiones']}') ?? 1;
      setState(() {
        _grupo = g;
        _id = '${j['id']}';
        _ctx = j['contexto'] is Map ? Map<String, dynamic>.from(j['contexto'] as Map) : _ctx;
        _plan = Map<String, dynamic>.from(j['planeacion'] as Map);
        _version = int.tryParse('${j['version']}') ?? vers;
        _quedan = vers >= 3 ? 0 : 3 - vers;
        _modeloVersion = '${j['modeloVersion'] ?? ''}';
        _avisos = [];
        _metricas = null;
        _paso = 3;
        _ocupado = false;
      });
      Future.microtask(_cargarAjustes);
      Future.microtask(_verificarBib);
    } catch (e) {
      if (mounted) setState(() { _ocupado = false; _error = _msgError(e); });
    }
  }

  Widget _tarjetasMisPlanes() {
    if (_misPlanes.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Tus planeaciones', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text('Ábrela para ver lo que ocurrió en cada clase y ajustar la siguiente sesión.',
          style: TextStyle(fontSize: 12, color: cessumMuted(context))),
      const SizedBox(height: 8),
      ..._misPlanes.take(6).map((p) => Card(
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.menu_book_outlined, color: cessumRed),
              title: Text('${p['materia']}', style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('Grupo ${p['grupo']} · ${p['sesiones']} sesiones · versión ${p['versiones']} · ${p['creado']}',
                  style: const TextStyle(fontSize: 11.5)),
              trailing: const Icon(Icons.chevron_right),
              onTap: _ocupado ? null : () => _abrirPlaneacion(p),
            ),
          )),
      const SizedBox(height: 14),
    ]);
  }

  Future<void> _abrirEncuadre() async {
    setState(() { _ocupado = true; _error = ''; });
    try {
      final g = _grupo!;
      final j = await _post({
        'accion': 'planea_contexto',
        'programa': g['programa'] ?? '', 'generacion': g['generacion'] ?? '',
        'grupo': g['grupo'] ?? '', 'materia': g['materia'] ?? '',
      });
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo leer la asignatura.');
      if (!mounted) return;
      setState(() {
        _ctx = j;
        _docente = '${(j['curricular'] as Map?)?['docente'] ?? ''}';
        _lit = ((j['literatura'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _litMax = int.tryParse('${j['literaturaMaximo'] ?? 12}') ?? 12;
        _litLibros = int.tryParse('${j['literaturaLibros'] ?? 5}') ?? 5;
        _litPaginas = int.tryParse('${j['literaturaPaginas'] ?? 50}') ?? 50;
        _preguntas = ((j['preguntas'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        // Directivo: las recomendaciones vienen ya elegidas. El docente
        // cambia lo que quiera, pero nunca arranca de cero.
        for (final p in _preguntas) {
          final rec = '${p['recomendada'] ?? ''}';
          if (p['tipo'] == 'multi') {
            _resp[p['id']] = rec.isEmpty ? <String>[] : rec.split(',');
          } else if (p['tipo'] == 'texto') {
            _libres[p['id']] = TextEditingController();
          } else if (rec.isNotEmpty) {
            _resp[p['id']] = rec;
          }
        }
        _paso = 2; _ocupado = false;
      });
      _buscarPendiente();
    } catch (e) {
      setState(() { _ocupado = false; _error = '$e'.replaceFirst('Exception: ', ''); });
    }
  }

  // ─────────────────────────────────────────────── GENERACIÓN POR PASOS
  /* (28-sep) LA PLANEACIÓN SE ESCRIBE UNA SESIÓN A LA VEZ.
     Antes se pedía todo de golpe y el servidor moría a los seis minutos: un
     curso de 14 semanas nunca terminaba, y lo avanzado se perdía. Ahora:
       1. planea_iniciar → el marco del curso (encuadre, dosificación de
          todas las sesiones, productos, evaluación).
       2. planea_sesion  → una llamada por sesión; cada una se guarda al
          terminar. Si una falla se reintenta sola una vez.
       3. planea_cerrar  → arma el documento, mide y avisa.
     Si algo se interrumpe, lo escrito queda guardado y se continúa desde
     ahí, en esta misma pantalla o al volver a entrar a la materia. */
  List<Map<String, String>> _respuestasActuales() => _preguntas.map((p) {
        final id = '${p['id']}';
        dynamic v = _resp[id];
        if (p['tipo'] == 'texto') v = _libres[id]?.text.trim() ?? '';
        if (v is List) v = v.join(',');
        return {'id': id, 'valor': '${v ?? ''}'};
      }).toList();

  String _msgError(Object e) {
    final t = '$e'.replaceFirst('Exception: ', '');
    if (t.contains('Timeout')) {
      return 'La respuesta tardó demasiado. Lo avanzado queda guardado: puedes continuar.';
    }
    if (t.contains('FormatException') || t.contains('Unexpected')) {
      return 'El servidor no respondió como se esperaba. Intenta de nuevo; lo avanzado queda guardado.';
    }
    return t;
  }

  Future<void> _generar() async {
    setState(() {
      _ocupado = true; _error = ''; _progDetenido = false;
      _progTotal = 0; _progHechas.clear(); _progPorHacer = [];
      _progNota = 'Armando el encuadre y la dosificación de todo el curso…';
    });
    _empezarEspera('planeación');
    try {
      final g = _grupo!;
      final j = await _post({
        'accion': 'planea_iniciar',
        'programa': g['programa'] ?? '', 'generacion': g['generacion'] ?? '',
        'grupo': g['grupo'] ?? '', 'materia': g['materia'] ?? '',
        'respuestas': _respuestasActuales(),
      }, seg: 600);
      // (9-oct-2026) CANDADO DE FUENTES: sin una fuente verificada de la materia el Guardián no genera.
      // No es un error: se abre el diálogo para subir, capturar o buscar fuentes y volver a intentar.
      if (j['requiereFuentes'] == true) {
        _terminarEspera();
        if (!mounted) return;
        setState(() { _ocupado = false; _progTotal = 0; _progNota = ''; });
        await _dialogoFuentesRequeridas('${j['error'] ?? ''}');
        return;
      }
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo iniciar la planeación.');
      if (!mounted) return;
      final total = int.tryParse('${j['total']}') ?? 0;
      setState(() {
        _id = '${j['id']}';
        _progVersion = 1;
        _progTotal = total;
        _progPorHacer = List<int>.generate(total, (i) => i + 1);
        _progRetro = '';
        _pendiente = null;
      });
      await _seguir(yaOcupado: true);
    } catch (e) {
      _terminarEspera();
      if (mounted) {
        setState(() { _ocupado = false; _progTotal = 0; _progNota = ''; _error = _msgError(e); });
      }
    }
  }

  Future<void> _seguir({bool yaOcupado = false}) async {
    if (!yaOcupado) {
      setState(() { _ocupado = true; _error = ''; _progDetenido = false; });
      _empezarEspera('planeación');
    }
    for (final n in List<int>.from(_progPorHacer)) {
      if (_progHechas.contains(n)) continue;
      if (!mounted) return;
      setState(() {
        _progActual = n;
        _progNota = _progVersion > 1
            ? 'Reescribiendo la sesión $n con tus cambios…'
            : 'Escribiendo la sesión $n de $_progTotal: inicio, desarrollo y cierre…';
      });
      var lista = false;
      var ultimoError = '';
      for (var intento = 1; intento <= 2 && !lista; intento++) {
        try {
          final j = await _post({
            'accion': 'planea_sesion', 'id': _id, 'sesion': '$n',
            'version': '$_progVersion',
            if (_progRetro.isNotEmpty) 'retro': _progRetro,
          }, seg: 420);
          if (j['ok'] == true) {
            lista = true;
          } else {
            ultimoError = '${j['error'] ?? 'No se pudo escribir la sesión $n.'}';
            if (j['reintentar'] != true) break;
          }
        } catch (e) {
          ultimoError = _msgError(e);
        }
        if (!lista && intento == 1 && mounted) {
          setState(() => _progNota = 'La sesión $n no salió completa. Reintentando…');
        }
      }
      if (!mounted) return;
      if (!lista) {
        _terminarEspera();
        setState(() {
          _ocupado = false;
          _progDetenido = true;
          _progNota = 'Se detuvo en la sesión $n. $ultimoError';
        });
        return;
      }
      setState(() => _progHechas.add(n));
    }
    if (!mounted) return;
    setState(() => _progNota = 'Revisando la planeación completa: proporción de interacciones, ponderaciones y temario…');
    try {
      final j = await _post({'accion': 'planea_cerrar', 'id': _id}, seg: 300);
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo armar la planeación.');
      _terminarEspera();
      if (!mounted) return;
      setState(() {
        _modeloVersion = '${j['modeloVersion'] ?? _modeloVersion}';
        _plan = Map<String, dynamic>.from(j['planeacion'] as Map);
        _version = int.tryParse('${j['version']}') ?? _progVersion;
        _quedan = int.tryParse('${j['quedan']}') ?? 0;
        _avisos = ((j['avisos'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _metricas = j['metricas'] is Map ? Map<String, dynamic>.from(j['metricas'] as Map) : null;
        _paso = 3;
        _ocupado = false;
        _progTotal = 0; _progHechas.clear(); _progPorHacer = [];
        _progDetenido = false; _progRetro = ''; _progNota = '';
        _retro.clear();
        // (5-oct-2026) Al terminar, la bibliografía se verifica sola contra las bases públicas.
        Future.microtask(_verificarBib);
        Future.microtask(_cargarAjustes);
      });
    } catch (e) {
      _terminarEspera();
      if (mounted) {
        setState(() {
          _ocupado = false;
          _progDetenido = true;
          _progNota = 'Las sesiones están escritas, pero no se pudo armar el documento. ${_msgError(e)}';
        });
      }
    }
  }

  /* ¿Quedó una planeación a medias de esta materia? */
  Future<void> _buscarPendiente() async {
    final g = _grupo;
    if (g == null) return;
    try {
      final j = await _post({
        'accion': 'planea_pendiente',
        'materia': g['materia'] ?? '', 'grupo': g['grupo'] ?? '',
      }, seg: 45);
      if (!mounted) return;
      setState(() => _pendiente = (j['ok'] == true && j['pendiente'] is Map)
          ? Map<String, dynamic>.from(j['pendiente'] as Map)
          : null);
    } catch (_) {
      // Sin respuesta no se ofrece continuar; el docente puede generar igual.
    }
  }

  List<int> _enteros(dynamic l) => ((l as List?) ?? [])
      .map((e) => int.tryParse('$e') ?? 0)
      .where((x) => x > 0)
      .toList();

  Future<void> _reanudar() async {
    final p = _pendiente;
    if (p == null) return;
    final porHacer = _enteros(p['porHacer']);
    final faltan = _enteros(p['faltan']);
    setState(() {
      _id = '${p['id']}';
      _progVersion = int.tryParse('${p['version']}') ?? 1;
      _progTotal = int.tryParse('${p['total']}') ?? porHacer.length;
      _progPorHacer = porHacer;
      _progHechas
        ..clear()
        ..addAll(porHacer.where((x) => !faltan.contains(x)));
      _progRetro = '${p['retro'] ?? ''}';
      _pendiente = null;
    });
    await _seguir();
  }

  Future<void> _revisar() async {
    final retro = _retro.text.trim();
    if (retro.length < 10) {
      setState(() => _error = 'Escribe qué quieres cambiar: al menos una frase.');
      return;
    }
    setState(() {
      _ocupado = true; _error = ''; _progDetenido = false; _progTotal = 0;
      _progNota = 'Leyendo tus cambios para decidir qué sesiones se reescriben…';
    });
    _empezarEspera('planeación');
    try {
      final j = await _post({'accion': 'planea_revisar_iniciar', 'id': _id, 'retro': retro}, seg: 600);
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo revisar.');
      if (!mounted) return;
      final rehacer = _enteros(j['rehacer']);
      setState(() {
        _progVersion = int.tryParse('${j['version']}') ?? _version + 1;
        _progTotal = int.tryParse('${j['total']}') ?? 0;
        _progPorHacer = rehacer;
        _progHechas.clear();
        _progRetro = retro;
        final porque = '${j['porque'] ?? ''}'.trim();
        _progNota = rehacer.isEmpty
            ? 'El cambio toca el marco del curso; las sesiones se conservan.'
            : 'Se reescriben ${rehacer.length == 1 ? 'la sesión' : 'las sesiones'} ${rehacer.join(', ')}. $porque';
      });
      await _seguir(yaOcupado: true);
    } catch (e) {
      _terminarEspera();
      if (mounted) {
        setState(() { _ocupado = false; _progTotal = 0; _progNota = ''; _error = _msgError(e); });
      }
    }
  }

  /* La plantilla en blanco, ya precargada con los datos curriculares de la
     asignatura y con una ficha por sesión. Para el docente que prefiere
     planear él mismo: no arranca de una hoja vacía ni captura lo que la
     institución ya sabe. */
  Future<void> _descargarPlantilla() async {
    setState(() { _ocupado = true; _error = ''; });
    try {
      // Los datos curriculares se piden aquí y el documento se arma en la
      // propia app: no hay pestaña intermedia ni archivo suelto en el
      // servidor que mantener aparte.
      final g = _grupo!;
      final j = await _post({
        'accion': 'planea_contexto',
        'programa': g['programa'] ?? '', 'generacion': g['generacion'] ?? '',
        'grupo': g['grupo'] ?? '', 'materia': g['materia'] ?? '',
      });
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo leer la asignatura.');
      final cuerpo = documentoPlantilla(contexto: j, docente: _docente);
      descargarWord(cuerpo, j, plantilla: true);
      if (!mounted) return;
      setState(() {
        _ocupado = false;
        _avisoEntregaOk = true;
        _avisoEntrega = 'Plantilla descargada en Word, con los datos de tu asignatura y una ficha '
            'por cada sesión. Llénala y vuelve aquí para enviarla.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ocupado = false;
        _error = 'No se pudo generar la plantilla: ${'$e'.replaceFirst('Exception: ', '')}';
      });
    }
  }

  Future<void> _cargarEntregas() async {
    try {
      final j = await _post({'accion': 'planea_mis_entregas'});
      if (!mounted) return;
      setState(() => _entregas = ((j['entregas'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map)).toList());
    } catch (_) {}
  }

  /* Firmar y enviar a Vicerrectoría. El docente se responsabiliza del
     documento: la firma queda registrada con su nombre, correo y fecha. */
  Future<void> _entregar({required String origen, String archivo = ''}) async {
    final g = _grupo!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Firmar y enviar'),
        content: Text(
          'Al enviarla, firmas esta planeación de "${g['materia']}" con tu nombre y queda a revisión de '
          'Vicerrectoría Académica.\n\nSi ya habías enviado una de esta materia, esta la sustituye.',
          style: const TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Firmar y enviar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() { _entregando = true; _avisoEntrega = ''; });
    try {
      final j = await _post({
        'accion': 'planea_entregar', 'origen': origen,
        'idPlaneacion': _id, 'archivo': archivo, 'version': '$_version',
        'programa': g['programa'] ?? '', 'generacion': g['generacion'] ?? '',
        'grupo': g['grupo'] ?? '', 'materia': g['materia'] ?? '', 'clave': g['clave'] ?? '',
      },
      // (10-sep) LA ENTREGA TARDA MÁS DE UN MINUTO.
      // Con 60 s la pantalla se rendía y mostraba «TimeoutException» aunque
      // del otro lado la entrega SÍ se había registrado y el correo ya había
      // salido. El docente creía que había fallado y volvía a darle al botón,
      // generando un reenvío que sustituía su propia entrega buena.
      seg: 240);
      if (!mounted) return;
      setState(() {
        _entregando = false;
        _avisoEntregaOk = j['ok'] == true;
        _avisoEntrega = '${j['nota'] ?? j['error'] ?? ''}';
      });
      if (j['ok'] == true) _cargarEntregas();
    } catch (e) {
      if (!mounted) return;
      setState(() { _entregando = false; _avisoEntregaOk = false; _avisoEntrega = 'No se pudo enviar: $e'; });
    }
  }

  /// Word y PDF se arman en la app con los datos que ya están en memoria:
  /// no hay que volver a pedirlos ni abrir otra pestaña.
  String _cuerpoDocumento() => documentoPlaneacion(
        contexto: _ctx ?? {},
        planeacion: _plan ?? {},
        docente: _docente,
        modeloVersion: _modeloVersion,
      );

  /* De la planeación a las diapositivas. Se pide el material ya armado de esa
     sesión —tema, criterio de logro, los tres momentos y los ABRIDORES ya
     escritos— y se abre el generador con eso cargado. El docente no vuelve a
     explicar el tema ni reinventa los abridores: la presentación sostiene lo
     que él planeó. */
  Future<void> _diapositivasDe(Map<String, dynamic> s) async {
    final n = s['sesion'];
    setState(() { _ocupado = true; _error = ''; });
    try {
      final j = await _post({
        'accion': 'planea_material_sesion', 'id': _id, 'sesion': '$n',
      });
      if (!mounted) return;
      // (9-sep) EL CANDADO DEL CICLO, dicho con claridad.
      // El Guardián ya no arma material sobre una planeación que Vicerrectoría
      // no ha autorizado. Antes eso hubiera salido como un error genérico y el
      // docente no habría sabido si era falla suya, de la app o del sistema.
      // Se explica en qué paso está y qué sigue, y se le ofrece ir a
      // entregarla si todavía no lo ha hecho.
      if (j['sinAutorizar'] == true) {
        setState(() => _ocupado = false);
        final estado = '${j['estadoEntrega'] ?? ''}';
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Primero la autorización'),
            content: Text('${j['error'] ?? ''}',
                style: const TextStyle(height: 1.4)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Entendido')),
              if (estado.isEmpty || estado == 'sin entregar')
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: cessumRed),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _entregar(origen: 'ia');
                  },
                  child: const Text('Entregar ahora'),
                ),
            ],
          ),
        );
        return;
      }
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo preparar la sesión.');
      setState(() => _ocupado = false);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GeneradorDiapositivasScreen(
            materialInicial: '${j['material'] ?? ''}',
            tituloInicial: '${j['tema'] ?? ''}',
            grupoInicial: {
              'programa': j['programa'] ?? '', 'generacion': j['generacion'] ?? '',
              'grupo': j['grupo'] ?? '', 'materia': j['materia'] ?? '',
            },
            dePlaneacion: _id,
            sesionDePlaneacion: int.tryParse('$n') ?? 0,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ocupado = false;
        _error = '${'$e'.replaceFirst('Exception: ', '')}';
      });
    }
  }

  /* Lo planeado contra lo que ocurrió. El dato es del docente primero: lo
     ve él, de su propia clase, y con el encuadre de que una desviación no es
     una falta. */
  Future<void> _contrasteDe(Map<String, dynamic> s) async {
    final n = s['sesion'];
    setState(() { _ocupado = true; _error = ''; });
    try {
      final j = await _post({'accion': 'planea_contraste', 'id': _id, 'sesion': '$n'});
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo comparar.');
      if (!mounted) return;
      setState(() => _ocupado = false);
      _verContraste(j, n);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ocupado = false;
        _error = '${'$e'.replaceFirst('Exception: ', '')}';
      });
    }
  }

  /* (5-oct-2026) LA PLANEACIÓN APRENDE DE LA CLASE REAL. Con el contraste de una clase analizada, la IA propone ajustes
     puntuales a la sesión siguiente; el docente acepta o descarta. Lo aceptado es una adenda: la planeación validada no
     cambia, y las presentaciones y materiales de esa sesión ya usan la versión ajustada. */
  Future<void> _cargarAjustes() async {
    if (_id.isEmpty) return;
    try {
      final j = await _post({'accion': 'planea_ajustes', 'id': _id});
      if (j['ok'] == true && mounted) {
        setState(() => _ajustes = ((j['ajustes'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList());
      }
    } catch (_) {}
  }

  // (8-oct-2026) `(a['destino'] as num?)` truena si el backend manda «destino» como texto
  // (p. ej. "3" en vez de 3) — y esta función se llama directo desde build(), sin try/catch,
  // así que ese error tumbaba toda la pantalla de la planeación. Ahora acepta número o texto.
  Map<String, dynamic>? _ajusteAceptadoDe(Object? sesion) {
    final n = int.tryParse('$sesion') ?? -1;
    int? destinoDe(Object? d) => d is num ? d.toInt() : int.tryParse('${d ?? ''}');
    final l = _ajustes.where((a) => a['estado'] == 'aceptado' && destinoDe(a['destino']) == n).toList();
    return l.isEmpty ? null : l.last;
  }

  Future<void> _proponerAjuste(Object? n) async {
    setState(() { _ocupado = true; _error = ''; });
    Map<String, dynamic> j;
    try {
      j = await _post({'accion': 'planea_ajuste_proponer', 'id': _id, 'sesion': '$n'}, seg: 300);
    } catch (e) {
      j = {'ok': false, 'error': _msgError(e)};
    }
    if (!mounted) return;
    setState(() => _ocupado = false);
    if (j['ok'] != true) {
      setState(() => _error = '${j['error'] ?? 'No se pudo proponer el ajuste.'}');
      return;
    }
    await _cargarAjustes();
    if (mounted) await _verAjuste(j);
  }

  Future<void> _verAjuste(Map<String, dynamic> a) async {
    final cambios = ((a['cambios'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final destino = a['sesionDestino'] ?? a['destino'];
    final antes = a['pctAntes'], despues = a['pctDespues'];
    final dec = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Ajuste sugerido para la sesión $destino'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${a['resumen'] ?? ''}', style: const TextStyle(fontSize: 13.5, height: 1.5, fontWeight: FontWeight.w600)),
              if (antes != null && despues != null) ...[
                const SizedBox(height: 8),
                Text('Interacciones complejas planeadas en esa sesión: $antes % → $despues %',
                    style: const TextStyle(fontSize: 12.5, color: Color(0xFF1E8E3E), fontWeight: FontWeight.w700)),
              ],
              const SizedBox(height: 10),
              for (final c in cambios)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: cessumGold.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${'${c['momento']}'.toUpperCase()} · ${c['tipo']}',
                        style: const TextStyle(fontSize: 10.5, letterSpacing: 1.1, fontWeight: FontWeight.w800, color: Color(0xFF8A5F10))),
                    if ('${c['antes'] ?? ''}'.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('Antes: ${c['antes']}', style: TextStyle(fontSize: 12, height: 1.4, color: cessumMuted(ctx))),
                    ],
                    const SizedBox(height: 4),
                    Text('Propuesta: ${c['despues']}', style: const TextStyle(fontSize: 12.5, height: 1.45)),
                    const SizedBox(height: 4),
                    Text('Por qué: ${c['porque']}', style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: cessumMuted(ctx))),
                  ]),
                ),
              Text('Si lo aceptas, la planeación validada no cambia: el ajuste queda como adenda y las presentaciones y materiales '
                  'de la sesión $destino ya lo usan.', style: TextStyle(fontSize: 11.5, color: cessumMuted(ctx), height: 1.4)),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Decidir después')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'descartar'), child: const Text('Descartar')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () => Navigator.pop(ctx, 'aceptar'),
              child: const Text('Aceptar ajuste')),
        ],
      ),
    );
    if (dec == null || !mounted) return;
    try {
      final r = await _post({'accion': 'planea_ajuste_decidir', 'id': _id, 'idAjuste': '${a['idAjuste'] ?? a['id']}', 'decision': dec});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: r['ok'] == true ? const Color(0xFF1E8E3E) : cessumRed,
          content: Text('${r['ok'] == true ? r['nota'] : r['error']}')));
      await _cargarAjustes();
    } catch (e) {
      if (mounted) setState(() => _error = _msgError(e));
    }
  }

  void _verContraste(Map<String, dynamic> j, Object? n) {
    final hay = j['hayMedicion'] == true;
    final pl = Map<String, dynamic>.from((j['planeado'] as Map?) ?? {});
    final oc = Map<String, dynamic>.from((j['ocurrio'] as Map?) ?? {});
    final hall = ((j['hallazgos'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final brecha = (j['brecha'] is num) ? (j['brecha'] as num).toDouble() : 0.0;

    showDialog(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 660),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
              decoration: BoxDecoration(
                color: cessumRed,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('LO QUE PLANEASTE Y LO QUE OCURRIÓ',
                        style: TextStyle(color: Colors.white70, fontSize: 10, letterSpacing: 1.3, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('Sesión $n · ${j['tema'] ?? ''}',
                        style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w700)),
                  ]),
                ),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white)),
              ]),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (!hay) ...[
                    _caja('${j['nota'] ?? ''}'),
                    const SizedBox(height: 10),
                    Text('Planeaste ${pl['pctComplejas'] ?? 0} % del tiempo en interacciones complejas, '
                        'con ${pl['abridoresComplejos'] ?? 0} abridor(es) de nivel 4 o 5.',
                        style: const TextStyle(fontSize: 13.5, height: 1.5)),
                  ] else ...[
                    // Las dos cifras, lado a lado. Sin flecha de «subió» o
                    // «bajó»: no es una carrera contra uno mismo.
                    Row(children: [
                      Expanded(child: _cifra('Planeaste', '${pl['pctComplejas'] ?? 0} %', cessumGold)),
                      const SizedBox(width: 10),
                      Expanded(child: _cifra('Ocurrió', '${oc['pctComplejas'] ?? 0} %',
                          brecha >= -8 ? const Color(0xFF1E8E3E) : cessumRed)),
                    ]),
                    const SizedBox(height: 12),
                    if (oc['porMomento'] != null) ...[
                      Text('POR MOMENTO DE LA CLASE',
                          style: TextStyle(fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: cessumMuted(context))),
                      const SizedBox(height: 6),
                      ...['inicio', 'desarrollo', 'cierre'].map((k) {
                        final m = Map<String, dynamic>.from(
                            ((oc['porMomento'] as Map?)?[k] as Map?) ?? {});
                        final p2 = (m['pct'] is num) ? (m['pct'] as num).toDouble() : 0.0;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Row(children: [
                            SizedBox(width: 78, child: Text(k,
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                            Expanded(
                              child: SizedBox(height: 9, child: LayoutBuilder(builder: (_, bc) => Stack(children: [
                                Container(decoration: BoxDecoration(color: cessumMuted(context).withValues(alpha: 0.18), borderRadius: BorderRadius.circular(3))),
                                FractionallySizedBox(
                                  widthFactor: (p2 / 100).clamp(0.0, 1.0),
                                  child: Container(decoration: BoxDecoration(
                                      color: p2 >= 40 ? const Color(0xFF1E8E3E) : cessumRed,
                                      borderRadius: BorderRadius.circular(3))),
                                ),
                                Positioned(left: bc.maxWidth * 0.40 - 1, top: 0, bottom: 0,
                                    child: Container(width: 1.5, color: cessumInk(context))),
                              ]))),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(width: 42, child: Text('${p2.toStringAsFixed(0)} %',
                                textAlign: TextAlign.right, style: const TextStyle(fontSize: 11.5))),
                          ]),
                        );
                      }),
                      const SizedBox(height: 12),
                    ],
                    ...hall.map((h) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: h['tipo'] == 'autocontestadas'
                                ? const Color(0xFFFBF1DC)
                                : const Color(0xFFF7F3EA),
                            border: Border(left: BorderSide(
                                color: h['tipo'] == 'autocontestadas' ? cessumGold : cessumMuted(context).withValues(alpha: 0.18),
                                width: 3)),
                          ),
                          child: Text('${h['texto']}',
                              style: const TextStyle(fontSize: 13, height: 1.5)),
                        )),
                  ],
                  const SizedBox(height: 8),
                  Text('${j['encuadre'] ?? ''}',
                      style: TextStyle(fontSize: 12, height: 1.5, fontStyle: FontStyle.italic,
                          color: cessumMuted(context))),
                  // (5-oct-2026) De lo que ocurrió, un ajuste concreto para la sesión siguiente.
                  if (hay) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: cessumGold, padding: const EdgeInsets.symmetric(vertical: 12)),
                        onPressed: () {
                          Navigator.pop(context);
                          _proponerAjuste(n);
                        },
                        icon: const Icon(Icons.auto_fix_high, size: 18),
                        label: Text('Ajustar la sesión ${(int.tryParse('$n') ?? 0) + 1} con esto'),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _cifra(String t, String v, Color c) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.08),
          border: Border.all(color: c.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.toUpperCase(),
              style: TextStyle(fontSize: 9.5, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: c)),
          const SizedBox(height: 3),
          Text(v, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: c, height: 1)),
          Text('del tiempo en complejas',
              style: TextStyle(fontSize: 10.5, color: cessumMuted(context))),
        ]),
      );

  void _descargarWord() {
    try {
      descargarWord(_cuerpoDocumento(), _ctx ?? {});
      setState(() {
        _avisoEntregaOk = true;
        _avisoEntrega = 'Descargada en Word. Ábrela y edítala como cualquier documento.';
      });
    } catch (e) {
      setState(() => _error = 'No se pudo generar el Word: $e');
    }
  }

  void _descargarPdf() {
    try {
      final abierta = imprimirPdf(_cuerpoDocumento(), _ctx ?? {});
      setState(() {
        if (abierta) {
          _avisoEntregaOk = true;
          _avisoEntrega = 'Se abre la ventana de impresión: elige «Guardar como PDF» como destino. '
              'Si no aparece, permite las ventanas emergentes de app.cessum.mx y vuelve a intentarlo.';
        } else {
          _avisoEntregaOk = false;
          _avisoEntrega = 'El navegador bloqueó la ventana del PDF. Permite las ventanas emergentes de '
              'app.cessum.mx y vuelve a tocar «Guardar como PDF».';
        }
      });
    } catch (e) {
      setState(() => _error = 'No se pudo generar el PDF: $e');
    }
  }

  // ─────────────────────────────────────────────── UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Planeación didáctica'),
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          // (9-oct-2026) Sin correo en la sesión, se explica qué hacer en vez de dejar que cada botón falle.
          : _sinCorreo
              ? _pantallaSinCorreo()
              : ListView(padding: const EdgeInsets.all(16), children: [
                  if (_error.isNotEmpty) _caja(_error, error: true),
                  // Va arriba de todo: mientras se genera, es lo único que
                  // importa ver, y así el docente sabe que sigue trabajando.
                  _barraEspera(),
                  if (_paso == 0) _pasoMateria(),
                  if (_paso == 1) ..._pasoRuta(),
                  if (_paso == 2) ..._pasoEncuadre(),
                  if (_paso == 3) ..._pasoPlan(),
                ]),
    );
  }

  /* (5-oct-2026) BIBLIOGRAFÍA VERIFICADA: cada referencia se busca en Crossref, Google Books y Open Library.
     Verificada / datos distintos (con lo encontrado) / no encontrada (no prueba que sea falsa) / literatura del docente. */
  Future<void> _verificarBib({bool avisar = false}) async {
    if (_id.isEmpty || _plan == null || _verificandoBib) return;
    final bib = ((_plan?['bibliografia'] as List?) ?? []);
    if (bib.isEmpty) return;
    setState(() => _verificandoBib = true);
    try {
      final j = await _post({'accion': 'planea_biblio_verificar', 'id': _id, 'version': '$_version'}, seg: 300);
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo verificar.');
      if (!mounted) return;
      setState(() => _plan = {...?_plan, 'bibliografia': j['bibliografia']});
      if (avisar) {
        final r = Map<String, dynamic>.from((j['resumen'] as Map?) ?? {});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Bibliografía: ${r['verificada'] ?? 0} verificada(s), ${r['datos_distintos'] ?? 0} con datos distintos, '
                '${r['no_encontrada'] ?? 0} no encontrada(s).')));
      }
    } catch (e) {
      if (avisar && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: cessumRed, content: Text('$e'.replaceFirst('Exception: ', ''))));
      }
    }
    if (mounted) setState(() => _verificandoBib = false);
  }

  Widget _chipBib(String t, Color c) => Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c)),
      );

  Widget _itemBib(Map<String, dynamic> b) {
    final ver = Map<String, dynamic>.from((b['verificacion'] as Map?) ?? {});
    final est = '${ver['estado'] ?? ''}';
    final enc = Map<String, dynamic>.from((ver['encontrado'] as Map?) ?? {});
    Widget chip;
    // (9-oct-2026) Las claves del canon: verificada (Crossref/Google Books/Open Library), texto del docente, aportada por él
    // (sin verificación automática) u obra del modelo registrada por Vicerrectoría.
    if (est == 'verificada') {
      chip = _chipBib('✓ verificada${'${ver['fuente'] ?? ''}'.isNotEmpty ? ' · ${ver['fuente']}' : ''}', const Color(0xFF1E7B34));
    } else if (b['de'] == 'modelo') {
      chip = _chipBib('obra del modelo', const Color(0xFF8A5F10));
    } else if (est == 'capturada') {
      chip = _chipBib('aportada por ti', const Color(0xFFB7791F));
    } else if (b['de'] == 'docente' || est == 'docente') {
      chip = _chipBib('tu literatura', const Color(0xFF8A5F10));
    } else if (est == 'datos_distintos') {
      chip = _chipBib('datos distintos', const Color(0xFFB7791F));
    } else if (est == 'no_encontrada') {
      chip = _chipBib('no encontrada', cessumRed);
    } else {
      chip = _chipBib(b['verificar'] == true ? 'sin verificar' : 'del programa', cessumMuted(context));
    }
    final datos = [
      if ('${enc['titulo'] ?? ''}'.isNotEmpty) '${enc['titulo']}',
      if (((enc['autores'] as List?) ?? []).isNotEmpty) ((enc['autores'] as List).take(3).join(', ')),
      if ((enc['anio'] ?? 0) != 0) '${enc['anio']}',
      if ('${enc['editorial'] ?? ''}'.isNotEmpty) '${enc['editorial']}',
      if ('${enc['doi'] ?? ''}'.isNotEmpty) 'DOI ${enc['doi']}',
      if ('${enc['isbn'] ?? ''}'.isNotEmpty) 'ISBN ${enc['isbn']}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text('${b['cita']}', style: const TextStyle(fontSize: 12.5, height: 1.4))),
          chip,
        ]),
        if (est == 'datos_distintos' && datos.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text('Lo que se encontró: $datos. ${ver['motivo'] ?? ''}', style: const TextStyle(fontSize: 11.5, color: Color(0xFFB7791F), height: 1.35)),
          ),
        if (est == 'no_encontrada')
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text('No aparece en Crossref, Google Books ni Open Library. No prueba que no exista: confírmala antes de usarla, o cámbiala.',
                style: TextStyle(fontSize: 11.5, color: cessumRed, height: 1.35)),
          ),
      ]),
    );
  }

  /* (9-oct-2026) Sin correo no se llama al Guardián: se dice qué pasó, qué hacer, y la materia con la que se
     venía (del Laboratorio de clases o de Mis planeaciones) se conserva para reintentar sin volver a elegirla. */
  Widget _pantallaSinCorreo() {
    final g = _grupo;
    const tinta = Color(0xFF8E141D);
    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFDEEF0),
          border: Border.all(color: const Color(0xFFE9B7BC)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.person_off_outlined, color: tinta),
            SizedBox(width: 8),
            Expanded(child: Text('No pude identificar tu correo',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: tinta))),
          ]),
          const SizedBox(height: 8),
          const Text(
            'La app no tiene tu correo en la sesión de este navegador, y sin él el Guardián no puede leer tu '
            'asignatura ni guardar tu planeación. Suele pasar cuando la sesión guardada caducó o cuando se entró en '
            '«Ver como profesor» con una cuenta que no tiene correo registrado.',
            style: TextStyle(fontSize: 13.5, height: 1.45, color: tinta),
          ),
          const SizedBox(height: 10),
          const Text(
            'Qué hacer: cierra sesión, vuelve a entrar con tu cuenta y abre de nuevo esta pantalla.',
            style: TextStyle(fontSize: 13.5, height: 1.45, fontWeight: FontWeight.w700, color: tinta),
          ),
          if (g != null) ...[
            const SizedBox(height: 10),
            Text(
              'Tu materia sigue aquí: ${g['materia'] ?? ''} · ${g['programa'] ?? ''} · '
              '${g['generacion'] ?? ''} · Grupo ${g['grupo'] ?? ''}',
              style: const TextStyle(fontSize: 12.5, height: 1.4, color: Color(0xFF6B5A2A)),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: () {
                setState(() { _cargando = true; _sinCorreo = false; });
                _cargar();
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Volver a intentar'),
            ),
            TextButton(
              onPressed: () => Navigator.maybePop(context),
              child: const Text('Regresar'),
            ),
          ]),
        ]),
      ),
    ]);
  }

  Widget _caja(String t, {bool error = false, bool ok = false, bool oro = false}) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: error ? const Color(0xFFFDEEF0) : ok ? const Color(0xFFF2F9F3) : const Color(0xFFFBF6EE),
          border: Border.all(color: error ? const Color(0xFFE9B7BC) : ok ? const Color(0xFFC7E4CE) : CC.goldBorder),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(t, style: TextStyle(fontSize: 13.5, height: 1.45,
            color: error ? const Color(0xFF8E141D) : ok ? const Color(0xFF1E7A38) : const Color(0xFF6B5A2A))),
      );

  Widget _boton(String t, VoidCallback? f, {bool sec = false}) => sec
      ? OutlinedButton(
          onPressed: _ocupado ? null : f,
          style: OutlinedButton.styleFrom(
              foregroundColor: cessumRed, side: BorderSide(color: cessumRed),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14)),
          child: Text(t))
      : ElevatedButton(
          onPressed: _ocupado ? null : f,
          style: ElevatedButton.styleFrom(
              backgroundColor: cessumRed, foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14)),
          child: _ocupado
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(t, style: const TextStyle(fontWeight: FontWeight.w700)));

  // Paso 0 · materia
  Widget _pasoMateria() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _tarjetasMisPlanes(),
        const Text('¿De qué asignatura?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('Los datos curriculares, los fines de aprendizaje, el temario y el número de sesiones se leen solos de la carta descriptiva.',
            style: TextStyle(fontSize: 13, color: cessumMuted(context))),
        const SizedBox(height: 14),
        if (_grupos.isEmpty)
          _caja('No tienes materias asignadas.')
        else ...[
          _buscadorMaterias(),
          const SizedBox(height: 10),
          _chipsFiltro(),
          const SizedBox(height: 12),
          if (_visibles.isEmpty)
            _caja(_buscar.text.trim().isNotEmpty
                ? 'Ninguna de tus materias coincide con «${_buscar.text.trim()}».'
                : (_filtro == 'vigentes'
                    ? 'No tienes materias vigentes. Toca «Terminadas» para planear una que ya cerró.'
                    : 'No tienes materias terminadas.')),
          ..._visibles.map((g) {
            final term = g['terminada'] == true;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text('${g['materia']}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${g['programa']} · ${g['generacion']} · Grupo ${g['grupo']}'),
                    if (term) ...[
                      const SizedBox(height: 4),
                      // Se dice que terminó y hace cuánto, en vez de esconderla:
                      // una materia cerrada todavía se puede planear, pero el
                      // docente debe saber en qué está entrando.
                      Text(
                        _leyendaTermino(g),
                        style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
                      ),
                    ],
                  ],
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => setState(() { _grupo = g; _paso = 1; }),
              ),
            );
          }),
        ],
      ]);

  // Materias que pasan el filtro y el texto del buscador.
  List<Map<String, dynamic>> get _visibles {
    final q = _norm(_buscar.text);
    return _grupos.where((g) {
      final term = g['terminada'] == true;
      if (_filtro == 'vigentes' && term) return false;
      if (_filtro == 'terminadas' && !term) return false;
      if (q.isEmpty) return true;
      // Se busca sobre todo junto: así «26-1 sabatino» encuentra igual que
      // el nombre de la materia, y no hay que acertarle al campo correcto.
      final heno = _norm('${g['materia']} ${g['programa']} ${g['generacion']} '
          '${g['grupo']} ${g['clave']} ${g['tipoSesiones']}');
      return q.split(' ').every((parte) => heno.contains(parte));
    }).toList();
  }

  int get _nVigentes => _grupos.where((g) => g['terminada'] != true).length;
  int get _nTerminadas => _grupos.where((g) => g['terminada'] == true).length;

  // Sin acentos y en minúsculas: escribir «pedagogia» debe encontrar
  // «Pedagogía».
  String _norm(String t) {
    const con = 'áéíóúüñÁÉÍÓÚÜÑ';
    const sin = 'aeiouunAEIOUUN';
    var r = t.toLowerCase();
    for (var i = 0; i < con.length; i++) {
      r = r.replaceAll(con[i], sin[i].toLowerCase());
    }
    return r.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _leyendaTermino(Map<String, dynamic> g) {
    final d = int.tryParse('${g['diasDesdeTermino'] ?? ''}') ?? -1;
    if (d < 0) return 'Terminada';
    if (d == 0) return 'Terminó hoy';
    if (d == 1) return 'Terminó ayer';
    if (d < 30) return 'Terminó hace $d días';
    final m = (d / 30).floor();
    return 'Terminó hace $m ${m == 1 ? 'mes' : 'meses'}';
  }

  Widget _buscadorMaterias() => TextField(
        controller: _buscar,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'Buscar materia, programa, generación o grupo',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _buscar.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _buscar.clear()),
                ),
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      );

  Widget _chipsFiltro() => Wrap(
        spacing: 8,
        children: [
          _chip('Vigentes', 'vigentes', _nVigentes),
          _chip('Terminadas', 'terminadas', _nTerminadas),
          _chip('Todas', 'todas', _grupos.length),
        ],
      );

  Widget _chip(String texto, String valor, int n) {
    final activo = _filtro == valor;
    return ChoiceChip(
      label: Text('$texto ($n)', style: const TextStyle(fontSize: 12.5)),
      selected: activo,
      selectedColor: cessumRed.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        color: activo ? cessumRed : cessumMuted(context),
        fontWeight: activo ? FontWeight.w700 : FontWeight.w500,
      ),
      side: BorderSide(
          color: activo ? cessumRed.withValues(alpha: 0.45) : cessumMuted(context).withValues(alpha: 0.18)),
      onSelected: (_) => setState(() => _filtro = valor),
    );
  }

  // Paso 1 · CÓMO QUIERE PLANEAR. Dos rutas legítimas: que la haga el
  // asistente, o hacerla él con la plantilla ya precargada. En las dos
  // desemboca en lo mismo: firmarla y enviarla a Vicerrectoría.
  List<Widget> _pasoRuta() {
    final g = _grupo ?? {};
    return [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: cessumRed, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${g['materia'] ?? ''}',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('${g['programa'] ?? ''} · ${g['generacion'] ?? ''} · Grupo ${g['grupo'] ?? ''}',
              style: const TextStyle(color: Color(0xFFF0D5D8), fontSize: 12.5)),
        ]),
      ),
      const SizedBox(height: 16),
      const Text('¿Cómo quieres planear?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text('Las dos rutas terminan igual: firmas tu planeación y la envías a Vicerrectoría para revisión.',
          style: TextStyle(fontSize: 13, color: cessumMuted(context))),
      const SizedBox(height: 14),
      _rutaCard(
        icono: Icons.auto_awesome,
        titulo: 'Crearla con el asistente',
        texto: 'Siete decisiones y el asistente redacta la planeación completa: dosificación, '
            'cada sesión en inicio, desarrollo y cierre, con los abridores y la evaluación. '
            'Puedes pedir hasta tres versiones.',
        boton: 'Empezar',
        onTap: _abrirEncuadre,
      ),
      _rutaCard(
        icono: Icons.download_outlined,
        titulo: 'Descargar la plantilla y hacerla yo',
        texto: 'La plantilla en Word ya trae tus datos curriculares, los fines de aprendizaje, '
            'el temario y una ficha por cada sesión de tu curso, con la estructura del modelo. '
            'Solo la llenas.',
        boton: 'Descargar plantilla',
        onTap: _descargarPlantilla,
        sec: true,
      ),
      const SizedBox(height: 6),
      _rutaCard(
        icono: Icons.upload_file_outlined,
        titulo: 'Ya la tengo hecha: subirla',
        texto: 'Si ya escribiste tu planeación, súbela a tu Drive, comparte el enlace y envíala '
            'firmada a Vicerrectoría desde aquí.',
        boton: 'Subir y enviar',
        onTap: _subirPropia,
        sec: true,
      ),
      if (_avisoEntrega.isNotEmpty) ...[
        const SizedBox(height: 10),
        _caja(_avisoEntrega, ok: _avisoEntregaOk, error: !_avisoEntregaOk),
      ],
      if (_entregas.isNotEmpty) ...[
        const SizedBox(height: 16),
        _titulo('Tus planeaciones entregadas'),
        ..._entregas.map(_tarjetaEntrega),
      ],
      const SizedBox(height: 12),
      _boton('Cambiar de materia', () => setState(() => _paso = 0), sec: true),
    ];
  }

  Widget _rutaCard({required IconData icono, required String titulo, required String texto,
      required String boton, required VoidCallback onTap, bool sec = false}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
          side: BorderSide(color: sec ? cessumMuted(context).withValues(alpha: 0.18) : cessumRed, width: sec ? 1 : 1.6)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icono, color: sec ? cessumGold : cessumRed, size: 24),
            const SizedBox(width: 10),
            Expanded(child: Text(titulo, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 7),
          Text(texto, style: TextStyle(fontSize: 13, height: 1.45, color: cessumMuted(context))),
          const SizedBox(height: 11),
          Align(alignment: Alignment.centerRight, child: _boton(boton, onTap, sec: sec)),
        ]),
      ),
    );
  }

  Widget _tarjetaEntrega(Map<String, dynamic> e) {
    final est = '${e['estado']}';
    final col = est == 'validada' ? const Color(0xFF1E8E3E)
        : est == 'con observaciones' ? const Color(0xFFB11D29) : cessumGold;
    final etq = est == 'validada' ? 'VALIDADA'
        : est == 'con observaciones' ? 'CON OBSERVACIONES' : 'EN REVISIÓN';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('${e['materia']}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: col.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
              child: Text(etq, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: col)),
            ),
          ]),
          Text('Folio ${e['folio']} · enviada ${e['entregada']}'
              '${'${e['revisor'] ?? ''}'.isNotEmpty ? ' · revisó ${e['revisor']}' : ''}',
              style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
          if ('${e['observaciones'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 7),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                  color: const Color(0xFFFBF6EE),
                  border: Border.all(color: CC.goldBorder),
                  borderRadius: BorderRadius.circular(7)),
              child: Text('${e['observaciones']}', style: const TextStyle(fontSize: 12.5, height: 1.45)),
            ),
          ],
        ]),
      ),
    );
  }

  /* Subir la planeación propia: el docente pega el enlace de su documento
     en Drive. Se pide enlace en vez de archivo porque el documento sigue
     siendo suyo y puede seguir editándolo; lo que la institución guarda es
     la referencia y la firma. */
  Future<void> _subirPropia() async {
    final c = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Subir tu planeación'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'Sube tu documento a Drive, compártelo con permiso de lectura para CESSUM y pega aquí el enlace.',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: c,
            decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'https://docs.google.com/…', isDense: true),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, c.text.trim()),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    if (!url.startsWith('http')) {
      setState(() { _avisoEntrega = 'El enlace no parece válido: debe empezar con http.'; _avisoEntregaOk = false; });
      return;
    }
    await _entregar(origen: 'propia', archivo: url);
  }

  // Paso 2 · encuadre curricular + preguntas directivas
  List<Widget> _pasoEncuadre() {
    final c = Map<String, dynamic>.from((_ctx?['curricular'] as Map?) ?? {});
    final dos = Map<String, dynamic>.from((_ctx?['dosificacion'] as Map?) ?? {});
    final temas = ((c['temas'] as List?) ?? []).map((e) => '$e').toList();
    return [
      // Lo que el sistema ya sabe. Se muestra para que el docente lo vea,
      // no para que lo capture.
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: cessumRed, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${c['denominacion'] ?? ''}',
              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text([
            if ('${c['clave'] ?? ''}'.isNotEmpty) '${c['clave']}',
            '${c['programa'] ?? ''}',
            '${c['modalidad'] ?? ''}',
            'Gen. ${c['generacion'] ?? ''}',
            'Grupo ${c['grupo'] ?? ''}',
            if ('${c['creditos'] ?? ''}'.isNotEmpty) '${c['creditos']} créditos',
          ].join(' · '), style: const TextStyle(color: Color(0xFFF0D5D8), fontSize: 12.5)),
          const SizedBox(height: 12),
          Row(children: [
            _kpi('${dos['sesiones'] ?? '—'}', 'sesiones'),
            const SizedBox(width: 24),
            _kpi('${temas.length}', 'temas del programa'),
          ]),
        ]),
      ),
      const SizedBox(height: 10),
      _caja('${dos['porque'] ?? ''}'),
      if (_ctx?['sinCarta'] == true)
        _caja('No se encontró la carta descriptiva de esta asignatura, así que no hay fines de aprendizaje ni temario oficiales. '
            'La planeación se puede generar igual, pero revísala con más cuidado: el contenido lo propondrá la IA, no el programa.',
            error: true),
      if (temas.isNotEmpty)
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('Temario oficial (${temas.length})',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          children: temas
              .map((t) => Padding(
                    padding: const EdgeInsets.only(bottom: 5, left: 4),
                    child: Text('· $t', style: const TextStyle(fontSize: 13)),
                  ))
              .toList(),
        ),
      if ('${c['fines'] ?? ''}'.isNotEmpty) ...[
        const SizedBox(height: 10),
        const Text('Fines de aprendizaje', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('${c['fines']}', style: const TextStyle(fontSize: 13, height: 1.5)),
      ],
      const SizedBox(height: 20),
      if (_pendiente != null) _tarjetaPendiente(),
      // (4-oct-2026) La literatura del docente: la base bibliográfica que la IA debe citar con páginas.
      _tarjetaPrefs(),   // (5-oct-2026) lo aprendido de sus versiones
      _seccionLiteratura(),
      const SizedBox(height: 20),
      const Text('Antes de generar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text('Nueve decisiones. Cada una viene con una recomendación y el porqué: cámbiala si tu grupo pide otra cosa.',
          style: TextStyle(fontSize: 13, color: cessumMuted(context))),
      const SizedBox(height: 12),
      ..._preguntas.map(_tarjetaPregunta),
      const SizedBox(height: 8),
      Row(children: [
        _boton('Atrás', () => setState(() => _paso = 1), sec: true),
        const SizedBox(width: 10),
        Expanded(child: _boton('Generar la planeación', _generar)),
      ]),
      const SizedBox(height: 8),
      Text('Se escribe una sesión a la vez (alrededor de un minuto cada una, son ${dos['sesiones'] ?? ''}). '
          'Verás el avance, y si algo se interrumpe lo escrito queda guardado.',
          style: TextStyle(fontSize: 12, color: cessumMuted(context))),
    ];
  }

  // ─────────────────────────────────────────────── LITERATURA DEL DOCENTE
  /* (4-oct-2026) Retroalimentación de un docente: la planeación no permitía vincular literatura externa
     (PDF de libros) y tomaba los contenidos sin relación explícita con literatura específica. Aquí el
     docente adjunta sus textos (o escribe una referencia); la IA hace una ficha de cada uno y la
     planeación los cita con páginas: en la dosificación, en cada sesión y en los productos. Las
     fichas quedan ligadas a la materia: sirven para todas las planeaciones de esa materia. */
  Future<Uint8List> _bytesDeArchivo(html.File f) async {
    final reader = html.FileReader()..readAsArrayBuffer(f);
    await reader.onLoad.first;
    final raw = reader.result;
    return raw is Uint8List ? raw : (raw as ByteBuffer).asUint8List();
  }

  /* (5-oct-2026) AGREGAR UN LIBRO, GUIADO. Máximo 5 libros por materia y 50 páginas por libro (los capítulos que se usarán).
     El docente da los datos que conozca; se le sugiere la portada y la página legal; «Completar con IA» llena lo que falte y
     lo confirma en Google Books, Open Library y Crossref. El PDF se cuenta aquí mismo antes de subirlo. */
  int get _librosSubidos => _lit.where((x) => x['tipo'] != 'referencia').length;

  int _paginasPdf(Uint8List bytes) {
    try {
      final s = latin1.decode(bytes, allowInvalid: true);
      final n = RegExp(r'/Type\s*/Page(?![a-zA-Z])').allMatches(s).length;
      if (n > 0) return n;
      var maxC = 0;
      for (final m in RegExp(r'/Type\s*/Pages[^>]*?/Count\s+(\d+)').allMatches(s)) {
        final k = int.tryParse(m.group(1) ?? '') ?? 0;
        if (k > maxC) maxC = k;
      }
      return maxC;
    } catch (_) {
      return 0;
    }
  }

  Future<html.File?> _elegirArchivo(String accept) async {
    final input = html.FileUploadInputElement()..accept = accept;
    input.click();
    await input.onChange.first;
    final fs = input.files ?? const <html.File>[];
    return fs.isEmpty ? null : fs.first;
  }

  Future<void> _litAgregarLibro() async {
    final g = _grupo!;
    final campos = <String, TextEditingController>{
      for (final k in const ['autores', 'anio', 'titulo', 'edicion', 'editorial', 'ciudad', 'isbn', 'fragmento']) k: TextEditingController(),
    };
    html.File? portada, legal, libro;
    Uint8List? libroBytes;
    var nota = '', notaError = false, completando = false, paginasLibro = 0;
    Map<String, String> completadoDe = {};

    Future<String?> b64De(html.File? f) async => f == null ? null : base64Encode(await _bytesDeArchivo(f));

    final subir = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          Widget campo(String k, String etiqueta, {String ayuda = '', int flex = 1}) => Expanded(
                flex: flex,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 8),
                  child: TextField(
                    controller: campos[k],
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: etiqueta,
                      hintText: ayuda,
                      border: const OutlineInputBorder(),
                      helperText: completadoDe[k] != null ? 'Completado de ${completadoDe[k]}' : null,
                      helperStyle: const TextStyle(color: Color(0xFF1E8E3E), fontSize: 10.5),
                    ),
                  ),
                ),
              );
          Widget adjunto(String t, html.File? f, VoidCallback onTap) => OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: f != null ? const Color(0xFF1E8E3E) : cessumRed),
                onPressed: onTap,
                icon: Icon(f != null ? Icons.check_circle : Icons.add_a_photo_outlined, size: 17),
                label: Text(f != null ? '$t: ${f.name}' : t, overflow: TextOverflow.ellipsis),
              );
          return AlertDialog(
            title: const Text('Agregar un libro'),
            content: SizedBox(
              width: 680,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _caja('Máximo $_litLibros libros por materia y $_litPaginas páginas por libro: sube solo los capítulos que vas a usar. '
                      'Llevas $_librosSubidos de $_litLibros.', oro: true),
                  const SizedBox(height: 10),
                  const Text('1. Datos del libro (los que conozcas)', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Row(children: [campo('autores', 'Autor(es)', ayuda: 'Freire, P.', flex: 2), campo('anio', 'Año', ayuda: '2005')]),
                  Row(children: [campo('titulo', 'Título', flex: 3), campo('edicion', 'Edición', ayuda: '2.ª')]),
                  Row(children: [campo('editorial', 'Editorial', flex: 2), campo('ciudad', 'Ciudad'), campo('isbn', 'ISBN')]),
                  Row(children: [campo('fragmento', 'Qué parte subes', ayuda: 'Caps. 1 y 2 (pp. 11-60)', flex: 3)]),
                  const SizedBox(height: 4),
                  const Text('2. Recomendado: la portada y la página legal', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('La página legal es la de los créditos (editorial, año, edición, ISBN), casi siempre al reverso de la portada. '
                      'Con ellas la IA completa y confirma los datos que falten. Puede ser foto o PDF.',
                      style: TextStyle(fontSize: 12, height: 1.4, color: cessumMuted(ctx))),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    adjunto('Portada', portada, () async { final f = await _elegirArchivo('image/*,.pdf'); if (f != null) setD(() => portada = f); }),
                    adjunto('Página legal', legal, () async { final f = await _elegirArchivo('image/*,.pdf'); if (f != null) setD(() => legal = f); }),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: cessumGold),
                      onPressed: completando
                          ? null
                          : () async {
                              setD(() { completando = true; nota = ''; });
                              try {
                                final j = await _post({
                                  'accion': 'planea_lit_datos', 'materia': g['materia'] ?? '',
                                  'bib': {for (final e in campos.entries) e.key: e.value.text.trim()},
                                  if (portada != null) 'portada_b64': await b64De(portada), if (portada != null) 'portada_mime': portada!.type,
                                  if (legal != null) 'legal_b64': await b64De(legal), if (legal != null) 'legal_mime': legal!.type,
                                }, seg: 180);
                                if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo completar.');
                                final bib = Map<String, dynamic>.from((j['bib'] as Map?) ?? {});
                                for (final c in ((j['completados'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map))) {
                                  completadoDe['${c['campo']}'] = '${c['de']}';
                                }
                                setD(() {
                                  for (final k in campos.keys) {
                                    if (campos[k]!.text.trim().isEmpty && '${bib[k] ?? ''}'.isNotEmpty) campos[k]!.text = '${bib[k]}';
                                  }
                                  final ver = Map<String, dynamic>.from((j['verificacion'] as Map?) ?? {});
                                  nota = '${j['nota'] ?? ''}${ver['estado'] == 'verificada' ? ' Confirmado en ${ver['fuente']}.' : ''}'
                                      '${'${j['referenciaApa'] ?? ''}'.isNotEmpty ? '\nReferencia: ${j['referenciaApa']}' : ''}';
                                  notaError = false;
                                });
                              } catch (e) {
                                setD(() { nota = _msgError(e); notaError = true; });
                              }
                              setD(() => completando = false);
                            },
                      icon: completando
                          ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.auto_awesome, size: 17),
                      label: Text(completando ? 'Completando…' : 'Completar con IA'),
                    ),
                  ]),
                  if (nota.isNotEmpty) ...[const SizedBox(height: 8), _caja(nota, error: notaError, ok: !notaError)],
                  const SizedBox(height: 12),
                  Text('3. El archivo del libro (PDF, Word o texto, máximo $_litPaginas páginas)', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Row(children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: libro != null ? const Color(0xFF1E8E3E) : cessumRed),
                      onPressed: () async {
                        final f = await _elegirArchivo('.pdf,.docx,.txt,.md,application/pdf');
                        if (f == null) return;
                        if (f.size > 20 * 1024 * 1024) { setD(() { nota = '«${f.name}» pasa de 20 MB.'; notaError = true; }); return; }
                        final bytes = await _bytesDeArchivo(f);
                        final esPdf = f.name.toLowerCase().endsWith('.pdf') || f.type.contains('pdf');
                        final n = esPdf ? _paginasPdf(bytes) : 0;
                        setD(() {
                          if (n > _litPaginas) {
                            libro = null; libroBytes = null; paginasLibro = n;
                            nota = '«${f.name}» tiene $n páginas y el máximo es $_litPaginas. Sube solo los capítulos que vas a usar.';
                            notaError = true;
                          } else {
                            libro = f; libroBytes = bytes; paginasLibro = n;
                          }
                        });
                      },
                      icon: Icon(libro != null ? Icons.check_circle : Icons.upload_file, size: 17),
                      label: Text(libro != null ? '${libro!.name}${paginasLibro > 0 ? ' · $paginasLibro páginas' : ''}' : 'Elegir el archivo'),
                    ),
                  ]),
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: cessumRed),
                onPressed: (libro == null || completando) ? null : () => Navigator.pop(ctx, true),
                child: const Text('Subir y hacer la ficha'),
              ),
            ],
          );
        },
      ),
    );
    if (subir != true || libro == null || libroBytes == null || !mounted) {
      for (final c in campos.values) { c.dispose(); }
      return;
    }
    final f = libro!;
    setState(() { _litOcupado = true; _litEstado = 'Leyendo «${f.name}» con IA (puede tardar un minuto)…'; });
    try {
      final j = await _post({
        'accion': 'planea_literatura_subir', 'programa': g['programa'] ?? '', 'materia': g['materia'] ?? '',
        'nombre': f.name, 'mime': f.type, 'datos_b64': base64Encode(libroBytes!),
        'bib': {for (final e in campos.entries) e.key: e.value.text.trim()},
        if (portada != null) 'portada_b64': await b64De(portada), if (portada != null) 'portada_mime': portada!.type,
        if (legal != null) 'legal_b64': await b64De(legal), if (legal != null) 'legal_mime': legal!.type,
      }, seg: 300);
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo leer el libro.');
      if (!mounted) return;
      setState(() {
        _lit.add({'id': j['id'], 'nombre': j['nombre'], 'tipo': j['tipo'], 'paginas': j['paginas'], 'ficha': j['ficha'], 'fecha': 'hoy'});
        _litEstado = 'Listo: «${f.name}» ya tiene su ficha.';
      });
    } catch (e) {
      if (mounted) setState(() => _litEstado = '«${f.name}»: ${_msgError(e)}');
    }
    for (final c in campos.values) { c.dispose(); }
    if (mounted) setState(() => _litOcupado = false);
  }

  Future<void> _litSubir() async {
    final input = html.FileUploadInputElement()
      ..accept = '.pdf,.docx,.txt,.md,application/pdf'
      ..multiple = true;
    input.click();
    await input.onChange.first;
    final fs = input.files ?? const <html.File>[];
    if (fs.isEmpty) return;
    final g = _grupo!;
    for (final f in fs) {
      if (!mounted) return;
      if (f.size > 20 * 1024 * 1024) {
        setState(() => _litEstado = '«${f.name}» pasa de 20 MB: sube solo la parte que vas a usar.');
        continue;
      }
      setState(() { _litOcupado = true; _litEstado = 'Leyendo «${f.name}» con IA (puede tardar un minuto)…'; });
      try {
        final bytes = await _bytesDeArchivo(f);
        final j = await _post({
          'accion': 'planea_literatura_subir',
          'programa': g['programa'] ?? '', 'materia': g['materia'] ?? '',
          'nombre': f.name, 'mime': f.type, 'datos_b64': base64Encode(bytes),
        }, seg: 300);
        if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo leer el texto.');
        if (!mounted) return;
        setState(() {
          _lit.add({'id': j['id'], 'nombre': j['nombre'], 'tipo': j['tipo'], 'paginas': j['paginas'], 'ficha': j['ficha'], 'fecha': 'hoy'});
          _litEstado = 'Listo: «${f.name}» ya tiene su ficha.';
        });
      } catch (e) {
        if (mounted) setState(() => _litEstado = '«${f.name}»: ${_msgError(e)}');
      }
    }
    if (mounted) setState(() => _litOcupado = false);
  }

  Future<void> _litReferencia() async {
    final ref = TextEditingController(), notas = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Agregar una referencia'),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Para un texto que no puedes adjuntar. Se busca en Crossref, Google Books y Open Library; si no aparece, '
                'te pregunto si respondes por ella antes de guardarla.',
                style: TextStyle(fontSize: 13, height: 1.4)),
            const SizedBox(height: 12),
            TextField(controller: ref, minLines: 2, maxLines: 4,
                decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Referencia (APA)', hintText: 'Autor, A. (año). Título. Editorial.')),
            const SizedBox(height: 10),
            TextField(controller: notas, minLines: 2, maxLines: 4,
                decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Qué usar y para qué (opcional)', hintText: 'Ej.: capítulos 2 y 3 para el tema 1; pp. 45-60 para el tema 4')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, ref.text.trim().isNotEmpty),
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _litGuardarReferencia(ref.text.trim(), notas.text.trim());
  }

  /* (9-oct-2026) El Guardián busca la referencia en Crossref, Google Books y Open Library. Si no la encuentra, no la
     guarda: pregunta si el docente responde por ella; solo entonces entra, marcada «aportada por ti». */
  Future<void> _litGuardarReferencia(String referencia, String notas, {bool confirmar = false}) async {
    final g = _grupo!;
    setState(() { _litOcupado = true; _litEstado = confirmar ? 'Guardando la referencia…' : 'Verificando la referencia en Crossref, Google Books y Open Library…'; });
    try {
      final j = await _post({
        'accion': 'planea_literatura_subir',
        'programa': g['programa'] ?? '', 'materia': g['materia'] ?? '',
        'referencia': referencia, 'notas': notas, if (confirmar) 'confirmar': '1',
      }, seg: 120);
      if (j['ok'] != true && j['noVerificada'] == true) {
        if (!mounted) return;
        setState(() { _litOcupado = false; _litEstado = ''; });
        final ver = Map<String, dynamic>.from((j['verificacion'] as Map?) ?? {});
        final enc = Map<String, dynamic>.from((ver['encontrado'] as Map?) ?? {});
        final parecida = [
          if ('${enc['titulo'] ?? ''}'.isNotEmpty) '${enc['titulo']}',
          if (((enc['autores'] as List?) ?? []).isNotEmpty) (enc['autores'] as List).take(3).join(', '),
          if ((enc['anio'] ?? 0) != 0) '${enc['anio']}',
          if ('${enc['editorial'] ?? ''}'.isNotEmpty) '${enc['editorial']}',
        ].join(' · ');
        final respondo = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('No pude verificar esa referencia'),
            content: SizedBox(
              width: 520,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${j['error'] ?? ''}', style: const TextStyle(fontSize: 13.5, height: 1.45)),
                if (parecida.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Lo parecido que encontré: $parecida', style: const TextStyle(fontSize: 12.5, height: 1.4, color: Color(0xFFB7791F))),
                ],
                const SizedBox(height: 10),
                Text('Si respondes por ella, entra a tus fuentes marcada «aportada por ti» y la IA la citará; si no, corrige autor, año o título y vuelve a agregarla.',
                    style: TextStyle(fontSize: 12.5, height: 1.4, color: cessumMuted(context))),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Corregirla')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Respondo por esta referencia'),
              ),
            ],
          ),
        );
        if (respondo == true && mounted) await _litGuardarReferencia(referencia, notas, confirmar: true);
        return;
      }
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo guardar.');
      if (!mounted) return;
      final est = '${((j['ficha'] as Map?)?['verificacion'] as Map?)?['estado'] ?? ''}';
      setState(() {
        _lit.add({'id': j['id'], 'nombre': j['nombre'], 'tipo': 'referencia', 'paginas': 0, 'ficha': j['ficha'], 'fecha': 'hoy'});
        _litEstado = est == 'verificada' ? 'Listo: referencia verificada.' : 'Listo: referencia guardada como aportada por ti.';
      });
    } catch (e) {
      if (mounted) setState(() => _litEstado = _msgError(e));
    }
    if (mounted) setState(() => _litOcupado = false);
  }

  /* (9-oct-2026) BUSCAR FUENTES VERIFICADAS. La IA propone a quién buscar; Crossref y Google Books dicen qué existe (solo
     obras con DOI o ISBN). El docente elige cuáles adoptar: nada entra sin que él lo marque. */
  Future<void> _litBuscar() async {
    final g = _grupo!;
    setState(() { _litOcupado = true; _litEstado = 'Buscando obras reales para este temario en Crossref y Google Books (hasta un minuto)…'; });
    Map<String, dynamic> j;
    try {
      j = await _post({'accion': 'planea_fuentes_buscar', 'programa': g['programa'] ?? '', 'materia': g['materia'] ?? '', 'max': '8'}, seg: 180);
    } catch (e) {
      j = {'ok': false, 'error': _msgError(e)};
    }
    if (!mounted) return;
    setState(() { _litOcupado = false; _litEstado = ''; });
    if (j['ok'] != true) { setState(() => _litEstado = '${j['error'] ?? 'No se pudo buscar.'}'); return; }
    final cands = ((j['candidatos'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (cands.isEmpty) { setState(() => _litEstado = '${j['nota'] ?? 'No encontré obras verificables para esta materia.'}'); return; }
    final cupo = _litMax - _lit.length;
    final elegidas = List<bool>.filled(cands.length, false);
    final adoptar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Fuentes verificadas encontradas'),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${cands.length} obra(s) reales para «${g['materia'] ?? ''}», con DOI o ISBN. Marca las que vas a usar: solo esas entran a tus fuentes'
                    '${cupo < cands.length ? ' (te caben $cupo más)' : ''}.',
                    style: const TextStyle(fontSize: 13, height: 1.45)),
                const SizedBox(height: 8),
                for (var i = 0; i < cands.length; i++)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: cessumRed,
                    value: elegidas[i],
                    onChanged: (v) => setD(() {
                      if (v == true && elegidas.where((x) => x).length >= cupo) return;
                      elegidas[i] = v ?? false;
                    }),
                    title: Text('${cands[i]['apa'] ?? cands[i]['titulo'] ?? ''}', style: const TextStyle(fontSize: 12.5, height: 1.35)),
                    subtitle: Text(
                        '${cands[i]['base'] ?? 'Crossref'}${'${cands[i]['doi'] ?? ''}'.isNotEmpty ? ' · DOI ${cands[i]['doi']}' : ''}'
                        '${'${cands[i]['isbn'] ?? ''}'.isNotEmpty ? ' · ISBN ${cands[i]['isbn']}' : ''}'
                        '${'${cands[i]['porQue'] ?? ''}'.isNotEmpty ? '\n${cands[i]['porQue']}' : ''}',
                        style: const TextStyle(fontSize: 11.5, height: 1.35)),
                  ),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
              onPressed: elegidas.any((x) => x) ? () => Navigator.pop(ctx, true) : null,
              child: Text('Agregar ${elegidas.where((x) => x).length} a mis fuentes'),
            ),
          ],
        ),
      ),
    );
    if (adoptar != true || !mounted) return;
    final sel = [for (var i = 0; i < cands.length; i++) if (elegidas[i]) cands[i]];
    setState(() { _litOcupado = true; _litEstado = 'Guardando ${sel.length} fuente(s)…'; });
    try {
      final a = await _post({'accion': 'planea_fuentes_adoptar', 'programa': g['programa'] ?? '', 'materia': g['materia'] ?? '', 'candidatos': sel}, seg: 120);
      if (a['ok'] != true) throw Exception(a['error'] ?? 'No se pudieron guardar.');
      if (!mounted) return;
      final nuevas = ((a['adoptadas'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      setState(() {
        for (final x in nuevas) {
          _lit.add({'id': x['id'], 'nombre': x['nombre'], 'tipo': 'referencia', 'paginas': 0, 'ficha': x['ficha'], 'fecha': 'hoy'});
        }
        _litEstado = 'Listo: ${nuevas.length} fuente(s) verificada(s) agregada(s)'
            '${(a['omitidas'] ?? 0) != 0 ? ' · ${a['omitidas']} omitida(s) por repetida o sin DOI/ISBN' : ''}.';
      });
    } catch (e) {
      if (mounted) setState(() => _litEstado = _msgError(e));
    }
    if (mounted) setState(() => _litOcupado = false);
  }

  /* (9-oct-2026) El candado, explicado, con las tres salidas. */
  Future<void> _dialogoFuentesRequeridas(String motivo) async {
    final accion = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Faltan fuentes verificadas'),
        content: SizedBox(
          width: 520,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(motivo.isNotEmpty ? motivo : 'Para generar la planeación hace falta al menos una fuente verificada de la materia.',
                style: const TextStyle(fontSize: 13.5, height: 1.45)),
            const SizedBox(height: 10),
            Text('La planeación, las presentaciones y el cuadernillo citan únicamente lo que esté en «Fuentes verificadas de la materia»: '
                'la IA no puede inventar bibliografía. Tienes tres caminos:',
                style: TextStyle(fontSize: 12.5, height: 1.4, color: cessumMuted(context))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('Cerrar')),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, 'libro'),
            icon: const Icon(Icons.library_add_outlined, size: 17),
            label: const Text('Subir un texto'),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, 'referencia'),
            icon: const Icon(Icons.format_quote, size: 17),
            label: const Text('Capturar referencia'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, 'buscar'),
            icon: const Icon(Icons.travel_explore, size: 17),
            label: const Text('Buscar fuentes verificadas'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (accion == 'libro') await _litAgregarLibro();
    if (accion == 'referencia') await _litReferencia();
    if (accion == 'buscar') await _litBuscar();
  }

  Future<void> _litQuitar(Map<String, dynamic> x) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar este texto'),
        content: Text('Dejará de usarse en las planeaciones de esta materia:\n\n${(x['ficha'] as Map?)?['referenciaApa'] ?? x['nombre']}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final j = await _post({'accion': 'planea_literatura_quitar', 'id': '${x['id']}'});
      if (j['ok'] != true) throw Exception(j['error'] ?? 'No se pudo quitar.');
      if (mounted) setState(() => _lit.removeWhere((e) => e['id'] == x['id']));
    } catch (e) {
      if (mounted) setState(() => _litEstado = _msgError(e));
    }
  }

  Widget _seccionLiteratura() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cessumGold.withValues(alpha: 0.45)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.menu_book_rounded, color: cessumGold, size: 22),
          const SizedBox(width: 8),
          const Expanded(child: Text('Fuentes verificadas de la materia', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
          Text('$_librosSubidos de $_litLibros libros', style: TextStyle(fontSize: 12, color: cessumMuted(context))),
        ]),
        const SizedBox(height: 4),
        // (9-oct-2026) La planeación, las presentaciones y el cuadernillo citan SOLO lo que esté aquí; la IA ya no propone
        // bibliografía propia. Sin al menos una fuente, el Guardián no genera (candado).
        Text('La planeación, las presentaciones y el cuadernillo citan únicamente lo que esté aquí: la IA no puede inventar bibliografía. '
            'Adjunta tus textos (la IA hace una ficha y los cita con páginas), captura referencias (se verifican en Crossref, Google Books y '
            'Open Library) o deja que el sistema busque obras reales para este temario. Sin al menos una fuente no se genera.',
            style: TextStyle(fontSize: 13, height: 1.45, color: cessumMuted(context))),
        const SizedBox(height: 10),
        if (_lit.isEmpty)
          _caja('Todavía no hay fuentes para esta materia: sin al menos una, la planeación no se genera.', error: true),
        for (final x in _lit) _tarjetaLiteratura(x),
        if (_litEstado.isNotEmpty) ...[
          const SizedBox(height: 6),
          _caja(_litEstado, error: _litEstado.contains('No se pudo') || _litEstado.contains('pasa de') || _litEstado.contains('más páginas'),
              ok: _litEstado.startsWith('Listo')),
        ],
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: cessumRed, foregroundColor: Colors.white),
            onPressed: (_litOcupado || _librosSubidos >= _litLibros || _lit.length >= _litMax) ? null : _litAgregarLibro,
            icon: _litOcupado
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.library_add_outlined, size: 18),
            label: Text(_litOcupado ? 'Leyendo…' : (_librosSubidos >= _litLibros ? 'Ya tienes $_litLibros libros' : 'Agregar un libro')),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: cessumRed),
            onPressed: (_litOcupado || _lit.length >= _litMax) ? null : _litReferencia,
            icon: const Icon(Icons.format_quote, size: 18),
            label: const Text('Capturar referencia'),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: cessumRed),
            onPressed: (_litOcupado || _lit.length >= _litMax) ? null : _litBuscar,
            icon: const Icon(Icons.travel_explore, size: 18),
            label: const Text('Buscar fuentes verificadas'),
          ),
        ]),
        const SizedBox(height: 6),
        Text('Máximo $_litLibros libros por materia y $_litPaginas páginas por libro: de un libro largo, sube solo los capítulos que vas a usar. '
            'Adjunta también la portada y la página legal para que la referencia quede completa y verificada.',
            style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
      ]),
    );
  }

  /* (9-oct-2026) Cómo se verificó cada fuente: texto adjunto · ✓ verificada (base) · aportada por ti · encontrada por el sistema. */
  Widget _chipFuente(Map<String, dynamic> x, Map<String, dynamic> f) {
    final ver = Map<String, dynamic>.from((f['verificacion'] as Map?) ?? {});
    final est = '${ver['estado'] ?? ''}';
    final origen = '${f['origen'] ?? ''}';
    String t; Color c;
    if (x['tipo'] != 'referencia') { t = 'texto adjunto'; c = const Color(0xFF8A5F10); }
    else if (est == 'verificada') { t = '✓ verificada${'${ver['fuente'] ?? ''}'.isNotEmpty ? ' · ${ver['fuente']}' : ''}'; c = const Color(0xFF1E7B34); }
    else if (est == 'capturada') { t = 'aportada por ti · sin verificación automática'; c = const Color(0xFFB7791F); }
    else { t = 'aportada por ti'; c = const Color(0xFFB7791F); }
    if (origen == 'busqueda') t = 'encontrada por el sistema · $t';
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(t, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c)),
    );
  }

  Widget _tarjetaLiteratura(Map<String, dynamic> x) {
    final f = Map<String, dynamic>.from((x['ficha'] as Map?) ?? {});
    final temas = ((f['temasQueCubre'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final conceptos = ((f['conceptosClave'] as List?) ?? []).map((e) => '$e').toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: const Color(0xFFFBF7EF), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(x['tipo'] == 'referencia' ? Icons.format_quote : Icons.picture_as_pdf_outlined, size: 18, color: cessumRed),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${f['referenciaApa'] ?? x['nombre'] ?? ''}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, height: 1.35)),
              _chipFuente(x, f),
            ]),
          ),
          IconButton(
            tooltip: 'Quitar',
            visualDensity: VisualDensity.compact,
            onPressed: _litOcupado ? null : () => _litQuitar(x),
            icon: Icon(Icons.close, size: 18, color: cessumMuted(context)),
          ),
        ]),
        if ('${f['resumen'] ?? ''}'.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 26, top: 2),
            child: Text('${f['resumen']}', maxLines: 3, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, height: 1.4, color: cessumMuted(context))),
          ),
        if (temas.isNotEmpty || conceptos.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 26, top: 6),
            child: Wrap(spacing: 6, runSpacing: 4, children: [
              for (final t in temas)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: cessumRed.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(20)),
                  child: Text('Tema ${t['tema']}${'${t['donde'] ?? ''}'.isNotEmpty ? ' · ${t['donde']}' : ''}',
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: cessumRed)),
                ),
              for (final c in conceptos.take(6))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(color: cessumGold.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                  child: Text(c, style: const TextStyle(fontSize: 10.5, color: Color(0xFF8A5F10))),
                ),
            ]),
          ),
      ]),
    );
  }

  Widget _kpi(String n, String t) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(n, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700, height: 1)),
        Text(t, style: const TextStyle(color: Color(0xFFF0D5D8), fontSize: 11.5)),
      ]);

  Widget _tarjetaPregunta(Map<String, dynamic> p) {
    final id = '${p['id']}';
    final tipo = '${p['tipo']}';
    final alerta = p['alerta'] is Map ? Map<String, dynamic>.from(p['alerta'] as Map) : null;
    final valor = _resp[id];
    final mostrarAlerta = alerta != null &&
        ((valor is String && valor == '${alerta['si']}') ||
            (valor is List && valor.contains('${alerta['si']}')));

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${p['texto']}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          if ('${p['analisis'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                  color: const Color(0xFFF7F3EA), borderRadius: BorderRadius.circular(7)),
              child: Text('${p['analisis']}',
                  style: TextStyle(fontSize: 12.5, height: 1.45, color: cessumInk(context))),
            ),
          ],
          const SizedBox(height: 10),
          if (tipo == 'opcion') ..._opciones(p, id),
          if (tipo == 'multi') _multi(p, id),
          if (tipo == 'numero') _numero(p, id),
          if (tipo == 'texto') _texto(p, id),
          if ('${p['porque'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.lightbulb_outline, size: 15, color: cessumGold),
              const SizedBox(width: 6),
              Expanded(
                child: Text('${p['porque']}',
                    style: TextStyle(fontSize: 12, height: 1.4, color: cessumMuted(context))),
              ),
            ]),
          ],
          if (mostrarAlerta) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: const Color(0xFFFDEEF0),
                border: Border.all(color: const Color(0xFFE9B7BC)),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.warning_amber_rounded, size: 16, color: Color(0xFF8E141D)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('${alerta['texto']}',
                      style: const TextStyle(fontSize: 12.5, height: 1.4, color: Color(0xFF8E141D))),
                ),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  List<Widget> _opciones(Map<String, dynamic> p, String id) {
    final ops = ((p['opciones'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final rec = '${p['recomendada'] ?? ''}';
    return ops.map((o) {
      final v = '${o['v']}';
      final sel = _resp[id] == v;
      return InkWell(
        onTap: () => setState(() => _resp[id] = v),
        borderRadius: BorderRadius.circular(9),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          decoration: BoxDecoration(
            color: sel ? cessumRed.withValues(alpha: 0.07) : null,
            border: Border.all(color: sel ? cessumRed : cessumMuted(context).withValues(alpha: 0.18), width: sel ? 1.6 : 1),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(children: [
            Icon(sel ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                size: 18, color: sel ? cessumRed : cessumFaint(context)),
            const SizedBox(width: 9),
            Expanded(child: Text('${o['t']}', style: const TextStyle(fontSize: 13.5))),
            if (v == rec)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                    color: cessumGold.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(20)),
                child: Text('sugerida',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: cessumGold)),
              ),
          ]),
        ),
      );
    }).toList();
  }

  Widget _multi(Map<String, dynamic> p, String id) {
    final ops = ((p['opciones'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final sel = (_resp[id] as List?)?.map((e) => '$e').toList() ?? <String>[];
    return Wrap(spacing: 6, runSpacing: 6, children: ops.map((o) {
      final v = '${o['v']}';
      return FilterChip(
        label: Text('${o['t']}', style: const TextStyle(fontSize: 12.5)),
        selected: sel.contains(v),
        selectedColor: cessumRed.withValues(alpha: 0.15),
        checkmarkColor: cessumRed,
        onSelected: (on) => setState(() {
          final l = List<String>.from(sel);
          if (on) { l.add(v); } else { l.remove(v); }
          _resp[id] = l;
        }),
      );
    }).toList());
  }

  Widget _numero(Map<String, dynamic> p, String id) {
    final min = int.tryParse('${p['min'] ?? 3}') ?? 3;
    final max = int.tryParse('${p['max'] ?? 6}') ?? 6;
    final rec = '${p['recomendada'] ?? ''}';
    return Wrap(spacing: 7, children: List.generate(max - min + 1, (i) {
      final v = '${min + i}';
      final sel = _resp[id] == v;
      return ChoiceChip(
        label: Text(v + (v == rec ? '  ·  sugerido' : ''), style: const TextStyle(fontSize: 13)),
        selected: sel,
        selectedColor: cessumRed.withValues(alpha: 0.15),
        onSelected: (_) => setState(() => _resp[id] = v),
      );
    }));
  }

  Widget _texto(Map<String, dynamic> p, String id) {
    _libres[id] ??= TextEditingController();
    return TextField(
      controller: _libres[id],
      minLines: 2, maxLines: 4,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        hintText: '${p['placeholder'] ?? ''}',
        isDense: true,
      ),
    );
  }

  // Paso 2 · la planeación
  List<Widget> _pasoPlan() {
    final enc = Map<String, dynamic>.from((_plan?['encuadre'] as Map?) ?? {});
    final dosi = ((_plan?['dosificacion'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final ses = ((_plan?['sesiones'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final acts = ((_plan?['actividades'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final bib = ((_plan?['bibliografia'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

    return [
      Row(children: [
        const Expanded(child: Text('Planeación lista', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: cessumGold.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
          child: Text('Versión $_version de 3', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ]),
      const SizedBox(height: 10),

      // El medidor de la proporción va PRIMERO: es el compromiso
      // institucional y lo que decide si la planeación sirve al modelo.
      if (_metricas != null) _medidor(),
      // Los avisos después: si algo no cuadra, que se vea antes de descargar.
      ..._avisos.map((a) => _caja('${a['texto']}',
          error: a['grave'] == true || a['tipo'] == 'ponderacion' || a['tipo'] == 'nivel')),

      // (5-oct-2026) Si el docente ajustó esta planeación por su cuenta, el generador aprende de sus cambios.
      Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: cessumGold.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Icon(Icons.school_outlined, color: Color(0xFF8A5F10)),
          const SizedBox(width: 10),
          Expanded(
            child: Text('¿Ajustaste esta planeación por tu cuenta? Sube tu versión y tus siguientes planeaciones saldrán más a tu manera.',
                style: TextStyle(fontSize: 12.5, height: 1.4, color: cessumInk(context))),
          ),
          TextButton(
            onPressed: (_aprendiendo || _id.isEmpty) ? null : _aprenderDeMiVersion,
            child: Text(_aprendiendo ? 'Comparando…' : 'Subir mi versión'),
          ),
        ]),
      ),
      Row(children: [
        Expanded(child: _boton('Descargar en Word', _descargarWord)),
        const SizedBox(width: 8),
        Expanded(child: _boton('Guardar como PDF', _descargarPdf, sec: true)),
      ]),
      const SizedBox(height: 10),
      // Firmar y enviar: el paso que convierte la planeación en documento
      // del expediente en vez de un archivo suelto.
      Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: const Color(0xFFFBF6EE),
          border: Border.all(color: CC.goldBorder),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Enviar a revisión', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Al firmarla queda a revisión de Vicerrectoría Académica y se incorpora al expediente del curso. '
              'Puedes seguir descargándola y editándola mientras no esté validada.',
              style: TextStyle(fontSize: 12.5, height: 1.45, color: cessumMuted(context))),
          const SizedBox(height: 10),
          // (10-sep) DÓNDE SE SUBE LA VERSIÓN CORREGIDA.
          // Sin decirlo, quien edita el Word en su computadora no tiene forma
          // de saber que debe volver AQUÍ: lo natural es suponer que basta con
          // guardar el archivo, o mandarlo por correo. El reenvío sustituye la
          // entrega anterior, así que conviene decir también eso.
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: const Color(0xFFFBF7EF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cessumGold.withValues(alpha: 0.45)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.upload_file_outlined, size: 16, color: cessumGold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Si la descargas y le haces cambios, la versión corregida se sube '
                  'DESDE ESTA MISMA PANTALLA, con «Subir la mía». No la mandes por '
                  'correo ni la guardes solo en tu computadora: la que se revisa es la '
                  'que está aquí. Al subirla sustituye a la entrega anterior.',
                  style: TextStyle(fontSize: 11.5, height: 1.45, color: cessumMuted(context)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          _boton(_entregando ? 'Enviando…' : 'Firmar y enviar a Vicerrectoría',
              _entregando ? null : () => _entregar(origen: 'ia')),
        ]),
      ),
      if (_avisoEntrega.isNotEmpty) ...[
        const SizedBox(height: 10),
        _caja(_avisoEntrega, ok: _avisoEntregaOk, error: !_avisoEntregaOk),
      ],
      const SizedBox(height: 16),

      if ('${enc['analisisFuncional'] ?? ''}'.isNotEmpty) ...[
        _titulo('Análisis funcional del propósito'),
        Text('${enc['analisisFuncional']}', style: const TextStyle(fontSize: 13.5, height: 1.5)),
        const SizedBox(height: 10),
      ],
      if ('${enc['proposito'] ?? ''}'.isNotEmpty) ...[
        _titulo('Criterio de logro del curso'),
        Text('${enc['proposito']}', style: const TextStyle(fontSize: 13.5, height: 1.5)),
        const SizedBox(height: 10),
      ],

      // (4-oct-2026) El proyecto que atraviesa el curso.
      if (_plan?['proyecto'] is Map && (_plan!['proyecto'] as Map)['hay'] == true) _tarjetaProyecto(Map<String, dynamic>.from(_plan!['proyecto'] as Map)),

      if (dosi.isNotEmpty) ...[
        _titulo('Dosificación'),
        ...dosi.map((d) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(radius: 12, backgroundColor: cessumRed,
                    child: Text('${d['sesion']}', style: const TextStyle(color: Colors.white, fontSize: 11))),
                const SizedBox(width: 9),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${d['tema']}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                  if ('${d['proposito'] ?? ''}'.isNotEmpty)
                    Text('${d['proposito']}', style: TextStyle(fontSize: 12, color: cessumMuted(context))),
                  // (4-oct-2026) Las lecturas de la fila, con páginas.
                  for (final l in ((d['lecturas'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)))
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('📖 ${l['ref'] ?? ''}${'${l['paginas'] ?? ''}'.isNotEmpty ? ' · ${l['paginas']}' : ''}${'${l['para'] ?? ''}'.isNotEmpty ? ' — ${l['para']}' : ''}',
                          style: const TextStyle(fontSize: 11.5, height: 1.35, color: Color(0xFF8A5F10))),
                    ),
                  if (d['sinLiteraturaDelDocente'] == true)
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Text('Ninguno de tus textos cubre este tema: la lectura es propuesta de la IA.',
                          style: TextStyle(fontSize: 11, color: Color(0xFF8E141D))),
                    ),
                ])),
                if ((d['nivel'] ?? 0) >= 4) _chipNivel(d['nivel']),
              ]),
            )),
        const SizedBox(height: 10),
      ],

      _titulo('Las sesiones'),
      ...ses.map(_tarjetaSesion),

      if (acts.isNotEmpty) ...[
        const SizedBox(height: 10),
        _titulo('Productos de aprendizaje'),
        ...acts.map((a) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('${a['numero']}. ${a['nombre']}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                    Text('${a['ponderacion']} %', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cessumGold)),
                  ]),
                  if ('${a['criterioDesempeno'] ?? ''}'.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text('Criterio de desempeño: ${a['criterioDesempeno']}',
                        style: const TextStyle(fontSize: 12.5, height: 1.4)),
                  ],
                  if ((a['nivel'] ?? 0) >= 4)
                    Padding(padding: const EdgeInsets.only(top: 5), child: _chipNivel(a['nivel'])),
                  if (a['esDelProyecto'] == true)
                    const Padding(padding: EdgeInsets.only(top: 5), child: Text('Entrega del proyecto del curso', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF8A5F10)))),
                  for (final l in ((a['lecturasBase'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)))
                    Padding(padding: const EdgeInsets.only(top: 3), child: Text('📖 ${l['ref'] ?? ''}${'${l['paginas'] ?? ''}'.isNotEmpty ? ' · ${l['paginas']}' : ''}', style: const TextStyle(fontSize: 11.5, color: Color(0xFF8A5F10)))),
                ]),
              ),
            )),
      ],

      if (bib.isNotEmpty) ...[
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _titulo('Bibliografía')),
          TextButton.icon(
            onPressed: _verificandoBib ? null : () => _verificarBib(avisar: true),
            icon: _verificandoBib
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.verified_outlined, size: 17),
            label: Text(_verificandoBib ? 'Verificando…' : 'Verificar'),
          ),
        ]),
        Text('Cada referencia se busca en Crossref, Google Books y Open Library.',
            style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
        const SizedBox(height: 6),
        ...bib.map(_itemBib),
      ],

      const SizedBox(height: 18),
      if (_quedan > 0) ...[
        _titulo('¿Cambios?'),
        Text('Escribe qué quieres distinto. Te ${_quedan == 1 ? 'queda 1 versión' : 'quedan $_quedan versiones'}.',
            style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
        const SizedBox(height: 8),
        TextField(
          controller: _retro, minLines: 2, maxLines: 5,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Ej.: la sesión 3 con más abridores de nivel 5; la actividad 2 anclada en su propia aula…',
          ),
        ),
        const SizedBox(height: 8),
        _boton('Pedir versión ${_version + 1}', _revisar),
      ] else
        _caja('Es la tercera versión, la última de esta planeación. Descárgala y edítala en Word, o empieza una nueva.'),
      const SizedBox(height: 14),
      _boton('Otra planeación', () => setState(() {
            _paso = 0; _plan = null; _id = ''; _version = 0; _quedan = 3; _avisoEntrega = '';
            _avisos = []; _resp.clear(); _libres.clear(); _error = '';
          }), sec: true),
    ];
  }

  /* El medidor. Lo primero que ve el docente: qué proporción de su clase
     va a interacciones complejas, y en qué sesiones se cae. El promedio
     solo no basta: una sesión brillante puede tapar tres simples. */
  Widget _medidor() {
    final g = Map<String, dynamic>.from((_metricas?['global'] as Map?) ?? {});
    final ses = ((_metricas?['sesiones'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final ab = Map<String, dynamic>.from((_metricas?['abridores'] as Map?) ?? {});
    final pct = (g['pct'] is num) ? (g['pct'] as num).toDouble() : 0.0;
    final cumple = _metricas?['cumple'] == true;
    final col = cumple ? const Color(0xFF1E8E3E) : cessumRed;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF6EE),
        border: Border.all(color: cumple ? const Color(0xFFC7E4CE) : const Color(0xFFE9B7BC), width: 1.5),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${pct.toStringAsFixed(1)} %',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: col, height: 1)),
          const SizedBox(width: 9),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text('del tiempo en interacciones complejas\nniveles 4 y 5 · mínimo institucional 40 %',
                  style: TextStyle(fontSize: 11.5, height: 1.3, color: cessumMuted(context))),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        // La barra con la marca del 40 %.
        LayoutBuilder(builder: (_, bc) {
          final w = bc.maxWidth;
          return SizedBox(
            height: 16,
            child: Stack(children: [
              Container(decoration: BoxDecoration(color: cessumMuted(context).withValues(alpha: 0.18), borderRadius: BorderRadius.circular(4))),
              FractionallySizedBox(
                widthFactor: (pct / 100).clamp(0.0, 1.0),
                child: Container(decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(4))),
              ),
              Positioned(left: w * 0.40 - 1, top: 0, bottom: 0,
                  child: Container(width: 2, color: cessumInk(context))),
            ]),
          );
        }),
        const SizedBox(height: 4),
        Text('${ab['complejos'] ?? 0} abridores complejos · ${ab['simples'] ?? 0} simples',
            style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
        if (ses.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('POR SESIÓN', style: TextStyle(fontSize: 9.5, letterSpacing: 1.2, fontWeight: FontWeight.w700, color: cessumMuted(context))),
          const SizedBox(height: 6),
          ...ses.map((x) {
            final p = (x['pct'] is num) ? (x['pct'] as num).toDouble() : 0.0;
            final bien = p >= 40;
            return Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(children: [
                SizedBox(width: 22, child: Text('${x['sesion']}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                Expanded(
                  child: SizedBox(
                    height: 9,
                    child: LayoutBuilder(builder: (_, bc) => Stack(children: [
                      Container(decoration: BoxDecoration(color: cessumMuted(context).withValues(alpha: 0.18), borderRadius: BorderRadius.circular(3))),
                      FractionallySizedBox(
                        widthFactor: (p / 100).clamp(0.0, 1.0),
                        child: Container(decoration: BoxDecoration(
                            color: bien ? const Color(0xFF1E8E3E) : cessumRed,
                            borderRadius: BorderRadius.circular(3))),
                      ),
                      Positioned(left: bc.maxWidth * 0.40 - 1, top: 0, bottom: 0,
                          child: Container(width: 1.5, color: cessumInk(context))),
                    ])),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(width: 46, child: Text('${p.toStringAsFixed(0)} %',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600,
                        color: bien ? const Color(0xFF1E8E3E) : cessumRed))),
                if (x['complejaEnDesarrollo'] != true)
                  Padding(padding: const EdgeInsets.only(left: 5),
                      child: Icon(Icons.warning_amber_rounded, size: 15, color: cessumRed)),
              ]),
            );
          }),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('La línea vertical marca el 40 %. El triángulo señala las sesiones cuya demanda compleja solo aparece en el cierre.',
                style: TextStyle(fontSize: 10.5, height: 1.35, color: cessumMuted(context))),
          ),
        ],
      ]),
    );
  }

  /// (4-oct-2026) El proyecto integrador: qué es, qué trae el estudiante de su práctica, el producto final y un hito por sesión.
  Widget _tarjetaProyecto(Map<String, dynamic> p) {
    final hitos = ((p['hitos'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final lect = ((p['lecturasBase'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF7EF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cessumGold.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.account_tree_outlined, color: cessumGold, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('Proyecto del curso: ${p['nombre'] ?? ''}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 6),
        Text('${p['queEs'] ?? ''}', style: const TextStyle(fontSize: 13.5, height: 1.5)),
        if ('${p['condicionDesligamiento'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Lo que trae de su práctica: ${p['condicionDesligamiento']}', style: const TextStyle(fontSize: 12.5, height: 1.4)),
        ],
        if ('${p['productoFinal'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Producto final: ${p['productoFinal']}', style: const TextStyle(fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w600)),
        ],
        if (hitos.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('Avance por sesión', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: .5)),
          const SizedBox(height: 4),
          for (final h in hitos)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(radius: 10, backgroundColor: cessumGold,
                    child: Text('${h['sesion']}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800))),
                const SizedBox(width: 8),
                Expanded(child: Text('${h['avance']}${'${h['evidencia'] ?? ''}'.isNotEmpty ? ' · Evidencia: ${h['evidencia']}' : ''}',
                    style: const TextStyle(fontSize: 12.5, height: 1.4))),
              ]),
            ),
        ],
        if ('${p['relacionConProductos'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('${p['relacionConProductos']}', style: TextStyle(fontSize: 12, height: 1.4, color: cessumMuted(context))),
        ],
        if (lect.isNotEmpty) ...[
          const SizedBox(height: 6),
          for (final l in lect)
            Text('📖 ${l['ref'] ?? ''}${'${l['paginas'] ?? ''}'.isNotEmpty ? ' · ${l['paginas']}' : ''}',
                style: const TextStyle(fontSize: 11.5, color: Color(0xFF8A5F10))),
        ],
      ]),
    );
  }

  Widget _titulo(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 4),
        child: Text(t.toUpperCase(),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1.1, color: cessumRed)),
      );

  Widget _chipNivel(dynamic n) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: cessumGold.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
        child: Text('nivel $n', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: cessumGold)),
      );

  // Cada sesión con sus tres momentos. Es la estructura que pidió
  // Vicerrectoría y la que el docente va a reconocer del diplomado.
  Widget _tarjetaSesion(Map<String, dynamic> s) {
    Widget momento(String nombre, Map<String, dynamic> m, Color color) {
      final acciones = ((m['acciones'] as List?) ?? []).map((e) => '$e').toList();
      final abridores = ((m['abridores'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 4, height: 14, color: color),
          const SizedBox(width: 7),
          Text(nombre, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .8, color: color)),
          const Spacer(),
          if ((m['minutos'] ?? 0) != 0)
            Text('${m['minutos']} min', style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
        ]),
        const SizedBox(height: 4),
        if ('${m['proposito'] ?? ''}'.isNotEmpty)
          Padding(padding: const EdgeInsets.only(left: 11, bottom: 4),
              child: Text('${m['proposito']}',
                  style: TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic, color: cessumMuted(context)))),
        ...acciones.map((a) => Padding(
              padding: const EdgeInsets.only(left: 11, bottom: 3),
              child: Text('· $a', style: const TextStyle(fontSize: 13, height: 1.4)),
            )),
        if ('${m['ruta'] ?? ''}'.isNotEmpty)
          Padding(padding: const EdgeInsets.only(left: 11, bottom: 4),
              child: Text('Lámina de propósito: ${m['ruta']}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.4))),
        if ('${m['condicionDesligamiento'] ?? ''}'.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(left: 11, top: 5),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: const Color(0xFFF7F3EA), borderRadius: BorderRadius.circular(7)),
            child: Text('Lo que el estudiante debe traer: ${m['condicionDesligamiento']}',
                style: const TextStyle(fontSize: 12, height: 1.4)),
          ),
        if ('${m['abridor'] ?? ''}'.isNotEmpty)
          _abridor('${m['abridor']}', m['abridorNivel'], '', {'tipoAbridor': m['abridorTipo'], 'tipoPregunta': m['preguntaTipo'], 'terminos': m['terminos']}),
        ...abridores.map((a) => _abridor('${a['texto']}', a['nivel'], '${a['cuando'] ?? ''}', a)),
        if ('${m['comoSostener'] ?? ''}'.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 11, top: 5),
            child: Text('Cómo sostenerlo: ${m['comoSostener']}',
                style: TextStyle(fontSize: 12, height: 1.4, color: cessumMuted(context))),
          ),
        if ('${m['respuestasEsperadas'] ?? ''}'.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 11, top: 4),
            child: Text('Respuestas esperadas: ${m['respuestasEsperadas']}',
                style: TextStyle(fontSize: 12, height: 1.4, color: cessumMuted(context))),
          ),
        if ('${m['evidenciaDeLogro'] ?? ''}'.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 11, top: 4),
            child: Text('Evidencia de logro: ${m['evidenciaDeLogro']}',
                style: TextStyle(fontSize: 12, height: 1.4, color: cessumMuted(context))),
          ),
        const SizedBox(height: 10),
      ]);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        subtitle: '${s['tipo'] ?? ''}'.isNotEmpty
            ? Text('${s['tipo']}${(s['semana'] ?? 0) != 0 ? ' · semana ${s['semana']}' : ''}'
                '${'${s['dia'] ?? ''}'.isNotEmpty ? ' · ${s['dia']}' : ''}',
                style: TextStyle(fontSize: 11.5, color: cessumMuted(context)))
            : null,
        title: Row(children: [
          CircleAvatar(radius: 13, backgroundColor: cessumRed,
              child: Text('${s['sesion']}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700))),
          const SizedBox(width: 9),
          Expanded(child: Text('${s['tema']}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
          if ((s['nivel'] ?? 0) != 0) _chipNivel(s['nivel']),
        ]),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        children: [
          if ('${s['criterioLogro'] ?? ''}'.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: const Color(0xFFFBF6EE),
                    border: Border.all(color: CC.goldBorder),
                    borderRadius: BorderRadius.circular(8)),
                child: Text('Criterio de logro: ${s['criterioLogro']}',
                    style: const TextStyle(fontSize: 12.5, height: 1.45)),
              ),
            ),
          momento('INICIO', Map<String, dynamic>.from((s['inicio'] as Map?) ?? {}), const Color(0xFF1E8E3E)),
          momento('DESARROLLO', Map<String, dynamic>.from((s['desarrollo'] as Map?) ?? {}), cessumRed),
          momento('CIERRE', Map<String, dynamic>.from((s['cierre'] as Map?) ?? {}), const Color(0xFFB0863A)),
          ...((s['recursos'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).where((r) => '${r['titulo'] ?? ''}'.isNotEmpty).map((r) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: const Color(0xFFF7F3EA), borderRadius: BorderRadius.circular(7)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${r['titulo']}${'${r['tipo'] ?? ''}'.isNotEmpty ? ' (${r['tipo']})' : ''}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                  if ('${r['ref'] ?? ''}'.isNotEmpty) Text('📖 ${r['ref']}', style: const TextStyle(fontSize: 12, height: 1.4, color: Color(0xFF8A5F10))),
                  if ('${r['para'] ?? ''}'.isNotEmpty) Text('Para qué: ${r['para']}', style: const TextStyle(fontSize: 12, height: 1.4)),
                  if ('${r['fragmento'] ?? ''}'.isNotEmpty) Text('Fragmento: ${r['fragmento']}', style: const TextStyle(fontSize: 12, height: 1.4)),
                  if ('${r['queObservar'] ?? ''}'.isNotEmpty) Text('Qué observar: ${r['queObservar']}', style: const TextStyle(fontSize: 12, height: 1.4)),
                  if ('${r['preguntaAntes'] ?? ''}'.isNotEmpty) Text('Pregunta antes: ${r['preguntaAntes']}', style: const TextStyle(fontSize: 12, height: 1.4, fontStyle: FontStyle.italic)),
                  if ('${r['preguntaDespues'] ?? ''}'.isNotEmpty) Text('Pregunta después: ${r['preguntaDespues']}', style: const TextStyle(fontSize: 12, height: 1.4, fontStyle: FontStyle.italic)),
                ]),
              )),
          if (s['avanceProyecto'] is Map && '${(s['avanceProyecto'] as Map)['hito'] ?? ''}'.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: cessumGold.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(7)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Avance del proyecto', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                Text('Hito: ${(s['avanceProyecto'] as Map)['hito']}', style: const TextStyle(fontSize: 12, height: 1.4)),
                if ('${(s['avanceProyecto'] as Map)['enSesion'] ?? ''}'.isNotEmpty)
                  Text('En la sesión: ${(s['avanceProyecto'] as Map)['enSesion']}', style: const TextStyle(fontSize: 12, height: 1.4)),
                if ('${(s['avanceProyecto'] as Map)['paraCasa'] ?? ''}'.isNotEmpty)
                  Text('Antes de la siguiente: ${(s['avanceProyecto'] as Map)['paraCasa']}', style: const TextStyle(fontSize: 12, height: 1.4)),
              ]),
            ),
          if ('${s['tarea'] ?? ''}'.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Tarea de la semana: ${s['tarea']}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: cessumRed,
                  side: BorderSide(color: cessumRed.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
              onPressed: _ocupado ? null : () => _diapositivasDe(s),
              icon: const Icon(Icons.slideshow_outlined, size: 17),
              label: const Text('Diapositivas de esta sesión',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          ),
          // (5-oct-2026) Sesión ajustada con lo que ocurrió en la clase anterior.
          // (8-oct-2026) Se resuelve una sola vez (antes se llamaba 4 veces para lo mismo) y se
          // protege contra «origen» ausente: antes, sin ese campo, el texto decía literalmente
          // "Ajustada con lo que ocurrió en la clase null: …".
          if (_ajusteAceptadoDe(s['sesion']) != null)
            Builder(builder: (_) {
              final aj = _ajusteAceptadoDe(s['sesion'])!;
              final origen = '${aj['origen'] ?? ''}';
              final resumen = '${aj['resumen'] ?? ''}';
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: [
                  const Icon(Icons.auto_fix_high, size: 15, color: Color(0xFF1E8E3E)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                        (origen.isEmpty || origen == '0')
                            ? resumen
                            : 'Ajustada con lo que ocurrió en la clase $origen: $resumen',
                        style: const TextStyle(fontSize: 11.5, color: Color(0xFF1E8E3E), height: 1.35)),
                  ),
                ]),
              );
            }),
          for (final p in _ajustes.where((a) => a['estado'] == 'propuesto' && '${a['destino']}' == '${s['sesion']}'))
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: const Color(0xFFB7791F), padding: const EdgeInsets.symmetric(horizontal: 6)),
                onPressed: () => _verAjuste({...p, 'sesionDestino': p['destino']}),
                icon: const Icon(Icons.pending_actions, size: 17),
                label: const Text('Hay un ajuste sugerido para esta sesión', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
            ),
          // (5-oct-2026) Sesiones de otros docentes sobre este tema, para usar o adaptar.
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: cessumRed, padding: const EdgeInsets.symmetric(horizontal: 6)),
              onPressed: (_ocupado || _id.isEmpty)
                  ? null
                  : () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => BibliotecaScreen(
                          destinoPlaneacionId: _id, destinoSesion: int.tryParse('${s['sesion']}'), destinoMateria: '${_grupo?['materia'] ?? ''}',
                          consultaInicial: '${s['tema'] ?? ''}', tipoInicial: 'planeacion_sesion')));
                      if (mounted) _cargarAjustes();
                    },
              icon: const Icon(Icons.local_library_outlined, size: 17),
              label: const Text('Bloques de la biblioteca para esta sesión', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                  foregroundColor: cessumGold, padding: const EdgeInsets.symmetric(horizontal: 6)),
              onPressed: _ocupado ? null : () => _contrasteDe(s),
              icon: const Icon(Icons.compare_arrows, size: 17),
              label: const Text('¿Qué ocurrió en esta clase?',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  // El abridor se pinta distinto de todo lo demás: es la pieza que el
  // docente tiene que poder localizar de un vistazo durante la clase.
  /// (4-oct-2026) Herramientas del diplomado: tipo de abridor, tipo de pregunta compleja y la conducción de cada pregunta.
  static const Map<String, String> _tipoAbrTxt = {'referir': 'Referir', 'significado': 'Significado', 'explicar': 'Explicar', 'anticipar': 'Anticipar'};
  static const Map<String, String> _tipoPregTxt = {'incorporacion': 'incorporación conceptual', 'derivacion': 'derivación del sistema', 'simple': 'simple'};
  Widget _abridor(String texto, dynamic nivel, String cuando, [Map<String, dynamic> x = const {}]) {
    String v(String k) => '${x[k] ?? ''}'.trim();
    final terminos = ((x['terminos'] as List?) ?? []).map((e) => '$e').where((e) => e.isNotEmpty).toList();
    final seguimiento = ((x['seguimiento'] as List?) ?? []).map((e) => '$e').where((e) => e.isNotEmpty).toList();
    final etiquetas = [
      if (_tipoAbrTxt[v('tipoAbridor')] != null) _tipoAbrTxt[v('tipoAbridor')]!,
      if (_tipoPregTxt[v('tipoPregunta')] != null) _tipoPregTxt[v('tipoPregunta')]!,
      if (v('modalidad').isNotEmpty) v('modalidad'),
    ];
    Widget linea(String t) => Padding(padding: const EdgeInsets.only(top: 3),
        child: Text(t, style: const TextStyle(fontSize: 11.5, height: 1.4, color: Color(0xFF5E544D))));
    return Container(
        margin: const EdgeInsets.only(left: 11, top: 6),
        padding: const EdgeInsets.all(9),
        decoration: const BoxDecoration(
          color: Color(0xFFFBF1DC),
          border: Border(left: BorderSide(color: Color(0xFFB0863A), width: 3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('ABRIDOR', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 1.3, color: cessumGold)),
            if ('$nivel' != '0' && '$nivel' != 'null')
              Text('  ·  nivel $nivel', style: TextStyle(fontSize: 9.5, color: cessumGold)),
            if (etiquetas.isNotEmpty)
              Flexible(child: Text('  ·  ${etiquetas.join(' · ')}', style: TextStyle(fontSize: 9.5, color: cessumGold), overflow: TextOverflow.ellipsis)),
            if (cuando.isNotEmpty)
              Expanded(child: Text('  ·  $cuando',
                  style: TextStyle(fontSize: 9.5, color: cessumGold), overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 3),
          Text(texto, style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, height: 1.4, color: Color(0xFF6B5A2A))),
          if (v('respuestaEsperada').isNotEmpty) linea('Respuesta esperada: ${v('respuestaEsperada')}'),
          if (terminos.isNotEmpty) linea('Términos que deben aparecer: ${terminos.join(', ')}'),
          if (v('siEsPertinente').isNotEmpty) linea('Si es pertinente: ${v('siEsPertinente')}'),
          if (v('siNoEsPertinente').isNotEmpty) linea('Si no es pertinente: ${v('siNoEsPertinente')}'),
          if (seguimiento.isNotEmpty) linea('Seguimiento: ${seguimiento.join(' · ')}'),
        ]),
      );
  }
}
