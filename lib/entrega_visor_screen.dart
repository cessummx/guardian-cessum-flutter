// =====================================================================
//  entrega_visor_screen.dart · CESSUM · App CESSUM
//  MESA DE REVISIÓN · R1 (4-oct-2026) — VER LA ENTREGA DEL ALUMNO.
//
//  Moodle, en el servidor compartido, no muestra bien los PDF ni los Word.
//  Aquí se muestran en el NAVEGADOR del docente, sin depender del servidor:
//    · PDF      → visor del navegador, incrustado (como en trámites y actas)
//    · Imagen   → con zoom (pellizcar o rueda) y giro
//    · Word     → con su formato (mammoth.js); si no carga, su texto
//    · Texto    → el texto en línea de la entrega y los .txt
//    · Otros    → su enlace directo en Moodle
//  Una pestaña por archivo. Ruta: entrega_ver (solo el docente de esa
//  entrega, por su sesión de Google, o un administrador).
//
//  R2 (4-oct-2026) — LO QUE LEYÓ LA IA. Junto a cada PDF o imagen, su
//  transcripción fiel (OCR incluido): [ilegible] en vez de adivinar,
//  [tachado: …], [figura: …], tablas, y la confianza de la lectura. El
//  docente la corrige y la marca como VERIFICADA; el borrador con IA evalúa
//  sobre esa lectura. Word y texto en línea ya son texto: no se leen.
//  Rutas: entrega_lecturas, entrega_leer (un archivo por llamada) y
//  entrega_lectura_guardar (POST).
//
//  R3 — Calificar y retroalimentar (CalificarEntregaScreen): guardado en el
//  libro de calificaciones de Moodle. R4 — Anotar y devolver
//  (AnotarEntregaScreen): el PDF anotado, adjunto como archivo de
//  retroalimentación.
// =====================================================================
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'revision_estilo.dart';   // (8-oct-2026) tipo de revisión con IA, para la sugerencia embebida

class EntregaVisorScreen extends StatefulWidget {
  final String llave;
  final String alumno;
  final String tarea;
  final String enlaceAula;
  /// (5-oct-2026) En ventana emergente (revisión por tarea): sin el pie de «Calificar».
  final bool compacto;
  /// (8-oct-2026) Al abrir, generar la calificación sugerida de inmediato en vez de esperar a que
  /// el docente toque «Generar con IA». Para el botón de un solo toque de la lista de pendientes,
  /// que antes abría el diálogo aparte de «Borrador con IA» (copiar y abrir el aula a mano, ya
  /// retirado — ver revisiones_screen.dart).
  final bool autoGenerarBorrador;
  const EntregaVisorScreen({
    super.key,
    required this.llave,
    this.alumno = '',
    this.tarea = '',
    this.enlaceAula = '',
    this.compacto = false,
    this.autoGenerarBorrador = false,
  });

  @override
  State<EntregaVisorScreen> createState() => _EntregaVisorScreenState();

  /* (5-oct-2026) VELOCIDAD: las entregas ya abiertas se recuerdan (reabrir es instantáneo) y la revisión por tarea
     precarga la siguiente mientras el docente lee la actual. Hasta 12 en memoria. */
  static final Map<String, Map<String, dynamic>> _memo = {};
  static final Map<String, Future<Map<String, dynamic>?>> _enCurso = {};

  static Future<Map<String, dynamic>?> traer(String llave, {bool forzar = false}) {
    if (!forzar && _memo.containsKey(llave)) return Future.value(_memo[llave]);
    if (!forzar && _enCurso.containsKey(llave)) return _enCurso[llave]!;
    final f = () async {
      try {
        final r = await http
            .get(Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'entrega_ver', 'llave': llave}))
            .timeout(const Duration(seconds: 150));
        final d = jsonDecode(r.body) as Map<String, dynamic>;
        if (d['ok'] == true) {
          if (_memo.length >= 12) _memo.remove(_memo.keys.first);
          _memo[llave] = d;
        }
        return d;
      } catch (_) {
        return null;
      } finally {
        _enCurso.remove(llave);
      }
    }();
    _enCurso[llave] = f;
    return f;
  }

  /// Precarga en segundo plano (no muestra nada).
  static void precargar(String llave) {
    if (llave.isEmpty || _memo.containsKey(llave) || _enCurso.containsKey(llave)) return;
    traer(llave);
  }
}

class _Pieza {
  final String titulo;
  final String clase; // pdf | imagen | word | texto | otro
  final Map<String, dynamic> archivo;
  final String texto;
  _Pieza(this.titulo, this.clase, this.archivo, {this.texto = ''});
}

class _EntregaVisorScreenState extends State<EntregaVisorScreen> {
  bool _cargando = true;
  String _error = '';
  Map<String, dynamic> _d = {};
  List<_Pieza> _piezas = [];
  final Map<int, String> _urls = {}; // blob: por pieza
  final Map<int, int> _giro = {}; // cuartos de vuelta por imagen
  // R2 · lectura con IA
  final Map<String, Map<String, dynamic>> _lect = {}; // por nombre de archivo
  final Map<String, TextEditingController> _ctl = {};
  final Set<String> _leyendo = {};
  final Set<String> _guardando = {};
  List<String> _pendientes = [];
  bool _verLectura = false; // en pantallas angostas, alterna entrega / lectura
  // (8-oct-2026) R2.1 · CALIFICACIÓN SUGERIDA EN EL MISMO PANEL. Antes, «Lo que leyó la IA» solo transcribía
  // un archivo; eso sirve para cotejar, pero el docente quería ver aquí mismo lo que de verdad usa para
  // calificar: calificación, fortalezas, faltantes y un comentario editable, generados sobre la ENTREGA
  // completa (todos sus archivos contra la consigna o la rúbrica), igual que «Borrador con IA» en Revisiones
  // pendientes y que «Usar el borrador con IA» en Calificar y retroalimentar — es la misma ruta, entrega_ia_retro,
  // para no triplicar la lógica. La transcripción por archivo (R2) sigue disponible, pero como sección
  // secundaria y colapsable: sigue haciendo falta para corregir lo que la IA leyó mal antes de calificar.
  Map<String, dynamic>? _borrador;
  bool _generandoBorrador = false;
  EstiloRevisionIa _estilo = EstiloRevisionIa.actual.copia();
  final TextEditingController _retroSugerida = TextEditingController();
  bool _verTranscripcion = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    for (final u in _urls.values) {
      try {
        html.Url.revokeObjectUrl(u);
      } catch (_) {}
    }
    _retroSugerida.dispose();
    super.dispose();
  }

  // ── R2.1 · Calificación, retro y comentario sugeridos (toda la entrega) ──
  Future<void> _generarBorrador({EstiloRevisionIa? estilo}) async {
    final est = estilo ?? _estilo;
    setState(() => _generandoBorrador = true);
    Map<String, dynamic> d;
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {
            'accion': 'entrega_ia_retro',
            'llave': widget.llave,
            'estilo': jsonEncode(est.toJson()),
          }))
          .timeout(const Duration(seconds: 150));
      d = jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      d = {'ok': false, 'error': 'No se pudo conectar. Intenta de nuevo.'};
    }
    if (!mounted) return;
    setState(() => _generandoBorrador = false);
    if (d['ok'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: cessumRed, content: Text('${d['error'] ?? 'No se pudo generar la sugerencia.'}')));
      return;
    }
    setState(() {
      _borrador = d;
      _estilo = est;
      EstiloRevisionIa.actual = est;
      _retroSugerida.text = '${d['retro'] ?? ''}';
    });
    // (6-oct-2026) El borrador ya OCR automáticamente las imágenes sin lectura guardada: refresca el panel de transcripción.
    _cargarLecturas();
  }

  Future<void> _cambiarTipoYGenerar() async {
    final r = await mostrarEstiloRevisionIa(context, _estilo);
    if (r != null && mounted) _generarBorrador(estilo: r);
  }

  /// Abre «Calificar y retroalimentar» ya con esta sugerencia aplicada: no se vuelve a generar.
  Future<void> _calificarConSugerencia() async {
    final b = _borrador == null ? null : (Map<String, dynamic>.from(_borrador!)..['retro'] = _retroSugerida.text);
    final hecho = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CalificarEntregaScreen(
          llave: widget.llave,
          alumno: '${_d['alumno'] ?? widget.alumno}',
          tarea: '${_d['tarea'] ?? widget.tarea}',
          borradorInicial: b,
        ),
      ),
    );
    if (hecho == true && mounted) Navigator.pop(context, true);
  }

  Future<void> _cargar({bool forzar = false}) async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final d = await EntregaVisorScreen.traer(widget.llave, forzar: forzar) ?? {'ok': false, 'error': 'No se pudo conectar. Intenta de nuevo.'};
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo abrir la entrega.');
      final piezas = <_Pieza>[];
      final texto = '${d['texto'] ?? ''}'.trim();
      if (texto.isNotEmpty) piezas.add(_Pieza('Texto en línea', 'texto', const {}, texto: texto));
      for (final a in ((d['archivos'] as List?) ?? [])) {
        final m = Map<String, dynamic>.from(a as Map);
        final nombre = '${m['nombre'] ?? 'archivo'}';
        final tipo = '${m['tipo'] ?? ''}'.toLowerCase();
        final ext = nombre.contains('.') ? nombre.split('.').last.toLowerCase() : '';
        final tieneB64 = '${m['base64'] ?? ''}'.isNotEmpty;
        String clase = 'otro';
        if (tieneB64 && tipo == 'application/pdf') {
          clase = 'pdf';
        } else if (tieneB64 && tipo.startsWith('image/')) {
          clase = 'imagen';
        } else if (ext == 'docx' && (tieneB64 || '${m['texto'] ?? ''}'.isNotEmpty)) {
          clase = 'word';
        } else if ('${m['texto'] ?? ''}'.isNotEmpty) {
          clase = 'texto';
        }
        piezas.add(_Pieza(nombre, clase, m, texto: '${m['texto'] ?? ''}'));
      }
      if (!mounted) return;
      setState(() {
        _d = d;
        _piezas = piezas;
        _cargando = false;
      });
      _cargarLecturas();
      // (8-oct-2026) Atajo desde la lista de pendientes: generar la sugerencia sin esperar un toque más.
      if (widget.autoGenerarBorrador && _borrador == null && !forzar) _generarBorrador();
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _error = '$e'.replaceFirst('Exception: ', '');
        });
      }
    }
  }

  // ── R2 · Lectura con IA ─────────────────────────────────────────────
  void _aplicarLecturas(Map<String, dynamic> d) {
    for (final l in ((d['lecturas'] as List?) ?? [])) {
      final m = Map<String, dynamic>.from(l as Map);
      final k = '${m['archivo']}';
      _lect[k] = m;
      final c = _ctl.putIfAbsent(k, () => TextEditingController());
      c.text = '${m['texto'] ?? ''}';
    }
    _pendientes = ((d['pendientes'] as List?) ?? []).map((e) => '$e').toList();
  }

  Future<void> _cargarLecturas() async {
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'entrega_lecturas', 'llave': widget.llave}))
          .timeout(const Duration(seconds: 120));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] == true && mounted) setState(() => _aplicarLecturas(d));
    } catch (_) {}
  }

  /// Un archivo por llamada: ninguna se pasa del tiempo y se ve el avance.
  Future<void> _leer(String archivo, {bool rehacer = false}) async {
    setState(() => _leyendo.add(archivo));
    String? error;
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {
            'accion': 'entrega_leer',
            'llave': widget.llave,
            'archivo': archivo,
            if (rehacer) 'rehacer': '1',
          }))
          .timeout(const Duration(seconds: 170));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) {
        error = '${d['error'] ?? 'No se pudo leer.'}';
      } else {
        final f = ((d['fallos'] as List?) ?? []);
        if (f.isNotEmpty) error = '${(f.first as Map)['error'] ?? 'No se pudo leer.'}';
        if (mounted) setState(() => _aplicarLecturas(d));
      }
    } catch (_) {
      error = 'No se pudo conectar. Intenta de nuevo.';
    }
    if (!mounted) return;
    setState(() => _leyendo.remove(archivo));
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: cessumRed, content: Text('«$archivo»: $error')));
    }
  }

  Future<void> _leerTodo() async {
    for (final a in List<String>.from(_pendientes)) {
      if (!mounted) return;
      await _leer(a);
    }
  }

  Future<void> _guardarLectura(String archivo) async {
    setState(() => _guardando.add(archivo));
    String msg;
    bool bien = false;
    try {
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'entrega_lectura_guardar',
                'llave': widget.llave,
                'archivo': archivo,
                'texto': _ctl[archivo]?.text ?? '',
                'verificada': true,
              }))
          .timeout(const Duration(seconds: 90));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      bien = d['ok'] == true;
      msg = bien ? 'Lectura verificada. El borrador con IA evaluará sobre este texto.' : '${d['error'] ?? 'No se pudo guardar.'}';
    } catch (_) {
      msg = 'No se pudo conectar. Intenta de nuevo.';
    }
    if (!mounted) return;
    setState(() {
      _guardando.remove(archivo);
      if (bien) {
        final l = _lect[archivo] ?? {};
        l['verificada'] = true;
        l['texto'] = _ctl[archivo]?.text ?? '';
        l['ilegibles'] = RegExp(r'\[ilegible\]', caseSensitive: false).allMatches(l['texto'] as String).length;
        _lect[archivo] = l;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: bien ? const Color(0xFF1E7B34) : cessumRed, content: Text(msg)));
  }

  /// Un blob local (no sube nada a ningún servidor) para el visor del navegador.
  String _blob(int i, Uint8List bytes, String mime) {
    return _urls.putIfAbsent(i, () => html.Url.createObjectUrlFromBlob(html.Blob([bytes], mime)));
  }

  Uint8List _bytes(Map<String, dynamic> a) => base64Decode('${a['base64'] ?? ''}');

  String _htmlWord(String b64, String textoRespaldo) {
    final datos = jsonEncode(b64), respaldo = jsonEncode(textoRespaldo);
    return '<!doctype html><html lang="es"><head><meta charset="utf-8">'
        '<link href="https://fonts.googleapis.com/css2?family=Montserrat:wght@400;600;700&display=swap" rel="stylesheet">'
        '<style>body{font-family:Montserrat,Arial,sans-serif;max-width:860px;margin:24px auto;padding:0 22px 40px;line-height:1.65;color:#1F1A17;font-size:15px}'
        'img{max-width:100%;height:auto}table{border-collapse:collapse;margin:10px 0}td,th{border:1px solid #D8CDBB;padding:5px 8px;vertical-align:top}'
        'h1,h2,h3{color:#8E1620}#aviso{color:#6B6257;font-size:13px}pre{white-space:pre-wrap;font-family:inherit}</style>'
        '<script src="https://cdnjs.cloudflare.com/ajax/libs/mammoth/1.6.0/mammoth.browser.min.js"></script></head><body>'
        '<div id="o"><p id="aviso">Abriendo el documento…</p></div><pre id="t" style="display:none"></pre><script>'
        'var B=$datos,T=$respaldo;'
        'function fb(){document.getElementById("o").innerHTML="<p id=aviso>Se muestra el texto del documento (sin formato).</p>";'
        'var t=document.getElementById("t");t.textContent=T||"No se pudo leer el documento.";t.style.display="block";}'
        'try{var s=atob(B),u=new Uint8Array(s.length);for(var i=0;i<s.length;i++)u[i]=s.charCodeAt(i);'
        'mammoth.convertToHtml({arrayBuffer:u.buffer}).then(function(r){document.getElementById("o").innerHTML=r.value||"<p id=aviso>El documento está vacío.</p>";}).catch(fb);}'
        'catch(e){fb();}</script></body></html>';
  }

  void _descargar(int i, _Pieza p) {
    final a = p.archivo;
    if ('${a['base64'] ?? ''}'.isEmpty) {
      if ('${a['url'] ?? ''}'.isNotEmpty) Helpers.abrirUrlExterna('${a['url']}', context);
      return;
    }
    final url = _blob(i, _bytes(a), '${a['tipo'] ?? 'application/octet-stream'}');
    html.AnchorElement(href: url)
      ..download = p.titulo
      ..click();
  }

  void _abrirPestana(int i, _Pieza p) {
    final a = p.archivo;
    if ('${a['base64'] ?? ''}'.isEmpty) {
      if ('${a['url'] ?? ''}'.isNotEmpty) Helpers.abrirUrlExterna('${a['url']}', context);
      return;
    }
    html.window.open(_blob(i, _bytes(a), '${a['tipo'] ?? 'application/octet-stream'}'), '_blank');
  }

  @override
  Widget build(BuildContext context) {
    final titulo = '${_d['alumno'] ?? widget.alumno}';
    return DefaultTabController(
      length: _piezas.isEmpty ? 1 : _piezas.length,
      child: Scaffold(
        backgroundColor: cessumBg(context),
        appBar: _barraMarca(context, titulo.isEmpty ? 'Entrega' : titulo, '${_d['tarea'] ?? widget.tarea}',
          actions: [
            if (!_cargando && _pendientes.isNotEmpty)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: cessumGold),
                onPressed: _leyendo.isNotEmpty ? null : _leerTodo,
                icon: _leyendo.isNotEmpty
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: cessumGold))
                    : const Icon(Icons.document_scanner_outlined, size: 18),
                label: Text(_leyendo.isNotEmpty ? 'Leyendo…' : 'Leer con IA (${_pendientes.length})'),
              ),
            IconButton(tooltip: 'Volver a cargar', onPressed: _cargando ? null : () => _cargar(forzar: true), icon: const Icon(Icons.refresh)),
          ],
          pestanas: (!_cargando && _piezas.length > 1)
              ? TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  indicatorColor: cessumGold,
                  indicatorWeight: 3,
                  labelColor: cessumRed,
                  unselectedLabelColor: CC.muted,
                  labelStyle: CessumType.heading(12.5, weight: FontWeight.w700),
                  tabs: [for (final p in _piezas) Tab(height: 44, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(_icono(p.clase), size: 17), const SizedBox(width: 6), Text(_corto(p.titulo))]))],
                )
              : null,
        ),
        body: _cargando
            ? const CessumSkeletonList(count: 3)
            : _error.isNotEmpty
                ? CessumEmptyState(
                    icon: Icons.cloud_off_rounded,
                    title: 'No se pudo abrir la entrega',
                    subtitle: _error,
                    action: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: cessumRed),
                      onPressed: _cargar,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Intentar de nuevo'),
                    ),
                  )
                : Column(children: [
                    _encabezado(),
                    Expanded(
                      child: _piezas.isEmpty
                          ? _vacio(Icons.inbox_outlined, 'La entrega no tiene texto ni archivos.')
                          : TabBarView(physics: const NeverScrollableScrollPhysics(), children: [
                              for (var i = 0; i < _piezas.length; i++) _conLectura(i, _piezas[i]),
                            ]),
                    ),
                    if (!widget.compacto) _pie(),
                  ]),
      ),
    );
  }

  IconData _icono(String c) => c == 'pdf'
      ? Icons.picture_as_pdf_outlined
      : c == 'imagen'
          ? Icons.image_outlined
          : c == 'word'
              ? Icons.description_outlined
              : c == 'texto'
                  ? Icons.notes
                  : Icons.attach_file;

  String _corto(String t) => t.length > 26 ? '${t.substring(0, 23)}…' : t;

  Widget _vacio(IconData i, String t) => CessumEmptyState(icon: i, title: t);

  Widget _encabezado() {
    final vencida = _d['vencida'] == true;
    final consigna = '${_d['consigna'] ?? ''}'.trim();
    return Container(
      width: double.infinity,
      color: Theme.of(context).cardColor,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 6, children: [
          _pastilla(Icons.upload_file, 'Entregada: ${_d['entregada'] ?? ''}', cessumMuted(context)),
          if ('${_d['vence'] ?? ''}'.isNotEmpty) _pastilla(Icons.event, 'Vence: ${_d['vence']}', vencida ? cessumRed : cessumMuted(context)),
          if (vencida) _pastilla(Icons.lock_clock, 'La tarea ya cerró', cessumRed),
          if (_d['tieneRubrica'] == true) _pastilla(Icons.rule, 'Con rúbrica en Moodle', cessumGold),
          if (_d['calificacionMaxima'] != null) _pastilla(Icons.grade_outlined, 'Sobre ${_d['calificacionMaxima']}', cessumMuted(context)),
        ]),
        if (consigna.isNotEmpty)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Consigna de la tarea', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(consigna, style: const TextStyle(fontSize: 12.5, height: 1.5)),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
      ]),
    );
  }

  Widget _pastilla(IconData i, String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 14, color: c),
          const SizedBox(width: 5),
          Text(t, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c)),
        ]),
      );

  Widget _barraArchivo(int i, _Pieza p, {List<Widget> extra = const []}) => Container(
        color: Theme.of(context).cardColor,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: Row(children: [
          Icon(_icono(p.clase), size: 18, color: cessumRed),
          const SizedBox(width: 6),
          Expanded(child: Text(p.titulo, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700))),
          ...extra,
          // (R4) Anotar el PDF o la foto y devolverlo al aula como archivo de retroalimentación.
          if ((p.clase == 'pdf' || p.clase == 'imagen') && '${p.archivo['base64'] ?? ''}'.isNotEmpty)
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: cessumRed),
              onPressed: () async {
                final hecho = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AnotarEntregaScreen(
                      llave: widget.llave,
                      base64: '${p.archivo['base64']}',
                      mime: '${p.archivo['tipo'] ?? (p.clase == 'pdf' ? 'application/pdf' : 'image/jpeg')}',
                      nombre: p.titulo,
                      titulo: '${_d['tarea'] ?? widget.tarea} · ${_d['alumno'] ?? widget.alumno}',
                    ),
                  ),
                );
                if (hecho == true && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      backgroundColor: Color(0xFF1E7B34), content: Text('La retroalimentación anotada ya está en el aula.')));
                }
              },
              icon: const Icon(Icons.draw_outlined, size: 18),
              label: const Text('Anotar'),
            ),
          if (p.clase != 'texto' || p.archivo.isNotEmpty) ...[
            IconButton(tooltip: 'Abrir en otra pestaña', onPressed: () => _abrirPestana(i, p), icon: const Icon(Icons.open_in_new, size: 19)),
            IconButton(tooltip: 'Descargar', onPressed: () => _descargar(i, p), icon: const Icon(Icons.download, size: 19)),
          ],
        ]),
      );

  Widget _vista(int i, _Pieza p) {
    final a = p.archivo;
    switch (p.clase) {
      case 'pdf':
        return Column(children: [
          _barraArchivo(i, p),
          Expanded(child: _Iframe(src: _blob(i, _bytes(a), 'application/pdf'))),
        ]);
      case 'imagen':
        final giro = _giro[i] ?? 0;
        return Column(children: [
          _barraArchivo(i, p, extra: [
            IconButton(
              tooltip: 'Girar',
              onPressed: () => setState(() => _giro[i] = (giro + 1) % 4),
              icon: const Icon(Icons.rotate_right, size: 19),
            ),
          ]),
          Expanded(
            child: Container(
              color: const Color(0xFF2A211B),
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 6,
                child: Center(child: RotatedBox(quarterTurns: giro, child: Image.memory(_bytes(a), fit: BoxFit.contain))),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(4),
            child: Text('Pellizca o usa la rueda del ratón para acercar.', style: TextStyle(fontSize: 11, color: cessumMuted(context))),
          ),
        ]);
      case 'word':
        if ('${a['base64'] ?? ''}'.isNotEmpty) {
          final url = _urls.putIfAbsent(i, () => html.Url.createObjectUrlFromBlob(html.Blob([_htmlWord('${a['base64']}', p.texto)], 'text/html')));
          return Column(children: [_barraArchivo(i, p), Expanded(child: _Iframe(src: url))]);
        }
        return Column(children: [_barraArchivo(i, p), Expanded(child: _texto(p.texto, nota: 'Se muestra el texto del documento (sin formato).'))]);
      case 'texto':
        return Column(children: [if (p.archivo.isNotEmpty) _barraArchivo(i, p), Expanded(child: _texto(p.texto))]);
      default:
        final motivo = '${a['omitido'] ?? 'Este formato no se puede mostrar en la app.'}';
        return Column(children: [
          _barraArchivo(i, p),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.insert_drive_file_outlined, size: 44, color: cessumMuted(context)),
                  const SizedBox(height: 10),
                  Text(p.titulo, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('$motivo${a['bytes'] != null ? ' · ${(((a['bytes'] as num?) ?? 0) / 1048576).toStringAsFixed(1)} MB' : ''}',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: cessumMuted(context))),
                  const SizedBox(height: 12),
                  if ('${a['url'] ?? ''}'.isNotEmpty)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: cessumRed),
                      onPressed: () => Helpers.abrirUrlExterna('${a['url']}', context),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('Abrir desde el aula'),
                    ),
                ]),
              ),
            ),
          ),
        ]);
    }
  }

  /// La entrega y, junto a ella, la sugerencia de la IA. Ancho: lado a lado. Angosto: se alterna.
  /// (8-oct-2026) Antes solo se mostraba en pdf/imagen (lo que se podía OCR); ahora se muestra
  /// SIEMPRE, porque la sugerencia es de la entrega completa, no de este archivo — una entrega
  /// solo de Word o texto también necesita ver aquí su calificación sugerida, no solo por el
  /// botón de abajo. Lo que sí sigue siendo exclusivo de pdf/imagen es la transcripción OCR por
  /// archivo (ver _cuerpoSugerencia): en Word/texto el contenido ya se ve completo en el visor.
  Widget _conLectura(int i, _Pieza p) {
    return LayoutBuilder(builder: (ctx, cons) {
      if (cons.maxWidth >= 980) {
        return Row(children: [
          Expanded(child: _vista(i, p)),
          Container(width: 1, color: cessumMuted(context).withValues(alpha: 0.25)),
          SizedBox(width: (cons.maxWidth * 0.40).clamp(360.0, 560.0), child: _panelLectura(p)),
        ]);
      }
      return Column(children: [
        Material(
          color: Theme.of(context).cardColor,
          child: Row(children: [
            Expanded(
              child: TextButton.icon(
                onPressed: () => setState(() => _verLectura = false),
                icon: Icon(Icons.visibility_outlined, size: 18, color: _verLectura ? cessumMuted(context) : cessumRed),
                label: Text('Entrega', style: TextStyle(color: _verLectura ? cessumMuted(context) : cessumRed, fontWeight: FontWeight.w700)),
              ),
            ),
            Expanded(
              child: TextButton.icon(
                onPressed: () => setState(() => _verLectura = true),
                icon: Icon(Icons.auto_awesome, size: 18, color: _verLectura ? cessumRed : cessumMuted(context)),
                label: Text('Sugerencia IA', style: TextStyle(color: _verLectura ? cessumRed : cessumMuted(context), fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
        Expanded(child: _verLectura ? _panelLectura(p) : _vista(i, p)),
      ]);
    });
  }

  Widget _panelLectura(_Pieza p) {
    return Container(
      color: cessumBg(context),
      child: Column(children: [
        Container(
          width: double.infinity,
          color: Theme.of(context).cardColor,
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
          child: Row(children: [
            Icon(Icons.auto_awesome, size: 18, color: cessumGold),
            const SizedBox(width: 6),
            const Expanded(child: Text('Calificación y retroalimentación sugeridas', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
            if (_borrador != null)
              TextButton.icon(
                onPressed: _generandoBorrador ? null : _cambiarTipoYGenerar,
                icon: const Icon(Icons.tune, size: 15),
                label: Text(_estilo.etiqueta, style: const TextStyle(fontSize: 11.5)),
              ),
          ]),
        ),
        Expanded(child: SingleChildScrollView(child: _cuerpoSugerencia(p))),
      ]),
    );
  }

  /// El contenido del panel: la sugerencia de la IA (lo nuevo) arriba, y la transcripción del archivo
  /// (lo que había antes) debajo, colapsada — sigue sirviendo para corregir lo que la IA leyó mal.
  /// (8-oct-2026) La transcripción solo aplica a pdf/imagen (lo que pasa por OCR); en Word/texto el
  /// contenido ya se ve completo en el visor, así que esa sección secundaria no se muestra ahí.
  Widget _cuerpoSugerencia(_Pieza p) {
    final ocrable = p.clase == 'pdf' || p.clase == 'imagen';
    final b = _borrador;
    if (b == null) {
      return Padding(
        padding: const EdgeInsets.all(22),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Icon(Icons.auto_awesome, size: 40, color: cessumGold),
          const SizedBox(height: 10),
          const Text('Calificación sugerida', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 6),
          Text(
              'La IA lee la entrega completa —todos sus archivos, transcribiendo lo escrito a mano si hace falta— contra la '
              'consigna o la rúbrica, y propone una calificación, fortalezas, faltantes y un comentario para el alumno, editable. '
              'Tú decides si lo usas.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, height: 1.45, color: cessumMuted(context))),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: _generandoBorrador ? null : () => _generarBorrador(),
            icon: _generandoBorrador
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.auto_awesome, size: 18),
            label: Text(_generandoBorrador ? 'Generando… (puede tardar un minuto)' : 'Generar con IA'),
          ),
          if (ocrable) ...[
            const SizedBox(height: 18),
            Divider(color: cessumMuted(context).withValues(alpha: 0.2)),
            _botonTranscripcion(p),
            if (_verTranscripcion) _bloqueTranscripcion(p),
          ],
        ]),
      );
    }
    final max = b['calificacionMaxima'] ?? 10;
    final cal = b['calificacionEnEscala'];
    final fortalezas = ((b['fortalezas'] as List?) ?? []).map((x) => '$x').toList();
    final faltantes = ((b['faltantes'] as List?) ?? []).map((x) => '$x').toList();
    final porCriterio = ((b['porCriterio'] as List?) ?? []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
    final archivos = ((b['archivos'] as List?) ?? []).map((x) => '$x').toList();
    final fuente = const {
          'docente': 'Revisado con tus criterios para esta tarea.',
          'moodle': 'Revisado con la rúbrica de la tarea en Moodle.',
          'instruccion': 'Revisado con los criterios que la IA dedujo de la instrucción.',
        }['${b['fuenteCriterios'] ?? ''}'] ??
        'Revisado con la consigna de la tarea.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(cal == null ? '—' : '$cal', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: cessumRed)),
          Padding(padding: const EdgeInsets.only(bottom: 6, left: 4), child: Text('/ $max', style: TextStyle(fontSize: 14, color: cessumMuted(context)))),
          if (b['tareaCerrada'] == true)
            Padding(
              padding: const EdgeInsets.only(left: 10, bottom: 9),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: cessumGold.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                child: const Text('tarea cerrada', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ),
        ]),
        const SizedBox(height: 2),
        Text(fuente, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E7B34))),
        if (archivos.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Archivos que recibió la IA (${archivos.length}): ${archivos.join(' · ')}',
                style: TextStyle(
                    fontSize: 11.5, height: 1.35, color: archivos.any((x) => x.contains('NO LEÍDO')) ? cessumGold : cessumMuted(context))),
          ),
        if (fortalezas.isNotEmpty || faltantes.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final f in fortalezas) Text('+ $f', style: const TextStyle(fontSize: 12.5, height: 1.4)),
          for (final f in faltantes) Text('– $f', style: const TextStyle(fontSize: 12.5, height: 1.4, color: cessumRed)),
        ],
        if (porCriterio.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('Por criterio de la rúbrica', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
          for (final c in porCriterio)
            Text('• ${c['criterio']}: ${c['nivel']}${'${c['comentario'] ?? ''}'.isNotEmpty ? ' — ${c['comentario']}' : ''}',
                style: const TextStyle(fontSize: 12, height: 1.4)),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _retroSugerida,
          minLines: 4,
          maxLines: 10,
          style: const TextStyle(fontSize: 13),
          decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Retroalimentación para el alumno (editable)'),
        ),
        const SizedBox(height: 10),
        Row(children: [
          OutlinedButton.icon(
            onPressed: _generandoBorrador ? null : () => _generarBorrador(),
            icon: _generandoBorrador
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh, size: 17),
            label: const Text('Volver a generar'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              onPressed: _calificarConSugerencia,
              icon: const Icon(Icons.grading, size: 18),
              label: const Text('Usar esta calificación'),
            ),
          ),
        ]),
        if (ocrable) ...[
          const SizedBox(height: 14),
          Divider(color: cessumMuted(context).withValues(alpha: 0.2)),
          _botonTranscripcion(p),
          if (_verTranscripcion) _bloqueTranscripcion(p),
        ],
      ]),
    );
  }

  Widget _botonTranscripcion(_Pieza p) {
    final k = p.titulo, leido = _lect[k] != null;
    return InkWell(
      onTap: () => setState(() => _verTranscripcion = !_verTranscripcion),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Icon(_verTranscripcion ? Icons.expand_less : Icons.expand_more, size: 18, color: cessumMuted(context)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              _verTranscripcion
                  ? 'Ocultar la transcripción de «${p.titulo}»'
                  : (leido ? 'Ver y corregir la transcripción de «${p.titulo}»' : 'Transcribir «${p.titulo}» para cotejarla a mano'),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cessumMuted(context)),
            ),
          ),
        ]),
      ),
    );
  }

  /// (antes era todo el panel «Lo que leyó la IA»; ahora es su sección secundaria, colapsable.)
  Widget _bloqueTranscripcion(_Pieza p) {
    final k = p.titulo, l = _lect[k], leyendo = _leyendo.contains(k);
    if (l == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              'La IA transcribe fielmente lo que está escrito, también a mano, sin corregir ni completar: marca [ilegible] en vez de '
              'adivinar. Sirve para cotejar la entrega o para mejorar la lectura que usa la sugerencia de arriba.',
              style: TextStyle(fontSize: 12, height: 1.4, color: cessumMuted(context))),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: leyendo ? null : () => _leer(k),
            icon: leyendo
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.document_scanner_outlined, size: 17),
            label: Text(leyendo ? 'Leyendo… (puede tardar un minuto)' : 'Leer este archivo con IA'),
          ),
        ]),
      );
    }
    final conf = '${l['confianza'] ?? ''}';
    final cc = conf == 'alta' ? const Color(0xFF1E7B34) : conf == 'baja' ? cessumRed : cessumGold;
    final verif = l['verificada'] == true;
    final ileg = (l['ilegibles'] as num?)?.toInt() ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          _pastilla(Icons.speed, 'Confianza ${conf.isEmpty ? '—' : conf}', cc),
          _pastilla(Icons.help_outline, ileg == 0 ? 'Sin ilegibles' : '$ileg ilegible${ileg == 1 ? '' : 's'}', ileg == 0 ? const Color(0xFF1E7B34) : cessumGold),
          verif
              ? _pastilla(Icons.verified, 'Verificada${'${l['verificadaPor'] ?? ''}'.isNotEmpty ? ' por ${l['verificadaPor']}' : ''}', const Color(0xFF1E7B34))
              : _pastilla(Icons.pending_outlined, 'Sin verificar', cessumMuted(context)),
          if ('${l['fecha'] ?? ''}'.isNotEmpty) Text('${l['fecha']}', style: TextStyle(fontSize: 11, color: cessumMuted(context))),
        ]),
        const SizedBox(height: 6),
        Text('Compárala con la entrega. Corrige lo que la IA leyó mal o completa un [ilegible] solo si tú sí lo lees.',
            style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
        const SizedBox(height: 8),
        TextField(
          controller: _ctl.putIfAbsent(k, () => TextEditingController(text: '${l['texto'] ?? ''}')),
          minLines: 6,
          maxLines: 18,
          style: const TextStyle(fontSize: 13, height: 1.5),
          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
        ),
        const SizedBox(height: 8),
        Row(children: [
          OutlinedButton.icon(
            onPressed: leyendo ? null : () => _leer(k, rehacer: true),
            icon: leyendo
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh, size: 17),
            label: const Text('Volver a leer'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1E7B34)),
              onPressed: _guardando.contains(k) ? null : () => _guardarLectura(k),
              icon: const Icon(Icons.verified_outlined, size: 18),
              label: Text(_guardando.contains(k) ? 'Guardando…' : (verif ? 'Guardar correcciones' : 'Marcar como verificada')),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _texto(String t, {String nota = ''}) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (nota.isNotEmpty) Text(nota, style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
              if (nota.isNotEmpty) const SizedBox(height: 8),
              SelectableText(t.isEmpty ? '(sin texto)' : t, style: const TextStyle(fontSize: 14.5, height: 1.65)),
            ]),
          ),
        ),
      );

  Widget _pie() {
    final enlace = widget.enlaceAula.isNotEmpty ? widget.enlaceAula : '${_d['enlaceAula'] ?? ''}';
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, -3))],
        ),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Row(children: [
          // (R3) Calificar aquí: calificación, rúbrica, retro (con el borrador con IA) y aviso, guardados en el aula.
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: cessumRed,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: _calificarConSugerencia,
              icon: const Icon(Icons.grading, size: 18),
              label: const Text('Calificar y retroalimentar'),
            ),
          ),
          if (enlace.isNotEmpty) ...[
            const SizedBox(width: 8),
            IconButton.outlined(
              tooltip: 'Abrir en el aula',
              onPressed: () => Helpers.abrirUrlExterna(enlace, context),
              icon: const Icon(Icons.open_in_new, size: 19),
            ),
          ],
        ]),
      ),
    );
  }
}

/// El mismo patrón que trámites y actas: un iframe con el visor del navegador.
class _Iframe extends StatefulWidget {
  final String src;
  const _Iframe({required this.src});
  @override
  State<_Iframe> createState() => _IframeState();
}

class _IframeState extends State<_Iframe> {
  static final Set<String> _registradas = {};
  late final String _vista;

  @override
  void initState() {
    super.initState();
    _vista = 'entrega-${widget.src.hashCode}';
    if (!_registradas.contains(_vista)) {
      _registradas.add(_vista);
      // ignore: undefined_prefixed_name
      ui_web.platformViewRegistry.registerViewFactory(_vista, (int _) {
        return html.IFrameElement()
          ..src = widget.src
          ..style.border = 'none'
          ..style.width = '100%'
          ..style.height = '100%';
      });
    }
  }

  @override
  Widget build(BuildContext context) => HtmlElementView(viewType: _vista);
}

// =====================================================================
//  R3 (4-oct-2026) — CALIFICAR Y RETROALIMENTAR, Y GUARDARLO EN EL AULA.
//  Escribe en el libro de calificaciones de Moodle como lo haría Moodle:
//  calificación, retroalimentación y niveles de la rúbrica. El docente
//  decide si Moodle avisa al alumno. El borrador con IA llena todo de una
//  vez (sobre la lectura verificada de R2) y el docente lo ajusta.
//  Rutas: entrega_calificacion (GET), entrega_ia_retro (GET),
//  entrega_calificar (POST).
// =====================================================================
class CalificarEntregaScreen extends StatefulWidget {
  final String llave;
  final String alumno;
  final String tarea;
  // (8-oct-2026) Borrador ya generado desde el panel de sugerencia en Mesa de revisión,
  // para no volver a llamar a la IA si el docente ya lo generó y lo quiere usar tal cual.
  final Map<String, dynamic>? borradorInicial;
  const CalificarEntregaScreen({super.key, required this.llave, this.alumno = '', this.tarea = '', this.borradorInicial});
  @override
  State<CalificarEntregaScreen> createState() => _CalificarEntregaScreenState();
}

class _CalificarEntregaScreenState extends State<CalificarEntregaScreen> {
  bool _cargando = true, _guardando = false, _pidiendoIa = false;
  // (5-oct-2026) ¿La tarea tiene criterios de revisión del docente?
  String _criteriosTxt = '';
  // (5-oct-2026) De dónde salen los criterios: docente | moodle | instruccion | consigna.
  String _critFuente = '';
  String _critAuto = '';
  List<String> _rubMoodle = [];
  String _error = '';
  Map<String, dynamic> _e = {};
  List<Map<String, dynamic>> _rubrica = [];
  final Map<String, int> _nivel = {}; // criterioId → nivelId
  final _cal = TextEditingController();
  final _retro = TextEditingController();
  bool _avisar = true;
  Map<String, dynamic>? _ia; // último borrador

  static const Color _verde = Color(0xFF1E7B34);

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _cal.dispose();
    _retro.dispose();
    super.dispose();
  }

  double get _max => ((_e['calificacionMaxima'] as num?) ?? 10).toDouble();

  Future<void> _cargarCriterios() async {
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'entrega_criterios', 'llave': widget.llave}))
          .timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] == true && mounted) {
        setState(() {
          _criteriosTxt = '${d['texto'] ?? ''}';
          _critFuente = '${d['fuente'] ?? ''}';
          _critAuto = '${d['criteriosAuto'] ?? ''}';
          _rubMoodle = ((d['rubricaMoodle'] as List?) ?? []).map((x) => '$x').toList();
        });
      }
    } catch (_) {}
  }

  String _resumenCriterios() {
    final t = _criteriosTxt.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length > 90 ? '${t.substring(0, 90)}…' : t;
  }

  /// (5-oct-2026) La IA lee la tarea sola: rúbrica de Moodle si la hay; si no, criterios deducidos de la instrucción.
  String _textoSinCriterios() {
    final nRub = _rubMoodle.isNotEmpty ? _rubMoodle.length : _rubrica.length;
    if (nRub > 0) return 'La tarea tiene rúbrica en Moodle ($nRub criterio${nRub == 1 ? '' : 's'}): la IA la usa sola. Tus indicaciones son opcionales.';
    if (_critAuto.isNotEmpty) {
      final t = _critAuto.replaceAll(RegExp(r'RÚBRICA DEDUCIDA DE LA INSTRUCCIÓN\s*'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
      return 'Sin rúbrica en Moodle: la IA dedujo los criterios de la instrucción: ${t.length > 110 ? '${t.substring(0, 110)}…' : t}';
    }
    return 'Sin rúbrica en Moodle: al generar el borrador, la IA leerá la instrucción y deducirá los criterios (una sola vez para toda la tarea).';
  }

  Future<void> _editarCriterios() async {
    final cambio = await editarCriteriosRevision(context, widget.llave, tarea: '${_e['tarea'] ?? widget.tarea}');
    if (cambio) await _cargarCriterios();
  }

  Future<void> _cargar() async {
    _cargarCriterios();
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'entrega_calificacion', 'llave': widget.llave}))
          .timeout(const Duration(seconds: 120));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo leer la calificación del aula.');
      if (!mounted) return;
      setState(() {
        _e = d;
        _rubrica = ((d['rubrica'] as List?) ?? []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
        _avisar = d['avisaAlAlumno'] != false;
        if (d['calificacionActual'] != null) _cal.text = '${d['calificacionActual']}';
        _retro.text = '${d['retroActual'] ?? ''}';
        if (widget.borradorInicial != null) {
          // (8-oct-2026) Ya hay un borrador generado desde el panel de sugerencia:
          // se aplica directo, sin volver a llamar a la IA.
          _aplicarBorrador(Map<String, dynamic>.from(widget.borradorInicial!));
        }
        _cargando = false;
      });
    } catch (e) {
      if (mounted) setState(() { _cargando = false; _error = '$e'.replaceFirst('Exception: ', ''); });
    }
  }

  /// Como Moodle: (suma − mínima) / (máxima − mínima) × calificación máxima.
  double? get _calRubrica {
    if (_rubrica.isEmpty || _nivel.length < _rubrica.length) return null;
    double suma = 0, minS = 0, maxS = 0;
    for (final c in _rubrica) {
      final niv = ((c['niveles'] as List?) ?? []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
      if (niv.isEmpty) continue;
      final pts = niv.map((n) => ((n['puntos'] as num?) ?? 0).toDouble()).toList();
      minS += pts.reduce((a, b) => a < b ? a : b);
      maxS += pts.reduce((a, b) => a > b ? a : b);
      final el = niv.firstWhere((n) => (n['id'] as num?)?.toInt() == _nivel['${c['id']}'], orElse: () => {});
      suma += ((el['puntos'] as num?) ?? 0).toDouble();
    }
    if (maxS <= minS) return null;
    return ((suma - minS) / (maxS - minS) * _max * 100).roundToDouble() / 100;
  }

  /// (8-oct-2026) Aplica un borrador de IA (de aquí o ya generado desde el panel de
  /// sugerencia en Mesa de revisión) a los campos de esta pantalla.
  void _aplicarBorrador(Map<String, dynamic> d) {
    _ia = d;
    if ('${d['fuenteCriterios'] ?? ''}' == 'instruccion' && _critAuto.isEmpty) _cargarCriterios();
    _retro.text = '${d['retro'] ?? ''}';
    if (_rubrica.isEmpty && d['calificacionEnEscala'] != null) _cal.text = '${d['calificacionEnEscala']}';
    for (final x in ((d['porCriterio'] as List?) ?? [])) {
      final m = Map<String, dynamic>.from(x as Map);
      final cid = '${m['criterioId'] ?? ''}', nid = int.tryParse('${m['nivelId'] ?? ''}');
      final c = _rubrica.where((r) => '${r['id']}' == cid).toList();
      if (c.isEmpty || nid == null) continue;
      final valido = ((c.first['niveles'] as List?) ?? []).any((n) => ((n as Map)['id'] as num?)?.toInt() == nid);
      if (valido) _nivel[cid] = nid;
    }
  }

  Future<void> _usarIa() async {
    setState(() => _pidiendoIa = true);
    Map<String, dynamic> d;
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {
            'accion': 'entrega_ia_retro',
            'llave': widget.llave,
            'estilo': jsonEncode(EstiloRevisionIa.actual.toJson()),
          }))
          .timeout(const Duration(seconds: 150));
      d = jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      d = {'ok': false, 'error': 'No se pudo conectar. Intenta de nuevo.'};
    }
    if (!mounted) return;
    setState(() {
      _pidiendoIa = false;
      if (d['ok'] == true) _aplicarBorrador(d);
    });
    if (d['ok'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: cessumRed, content: Text('${d['error'] ?? 'No se pudo generar el borrador.'}')));
    }
  }

  Future<void> _guardar() async {
    final conRubrica = _rubrica.isNotEmpty;
    double? cal;
    if (conRubrica) {
      if (_nivel.length < _rubrica.length) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(backgroundColor: cessumRed, content: Text('Elige el nivel de cada criterio de la rúbrica.')));
        return;
      }
      cal = _calRubrica;
    } else {
      cal = double.tryParse(_cal.text.trim().replaceAll(',', '.'));
      if (cal == null || cal < 0 || cal > _max) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: cessumRed, content: Text('La calificación debe estar entre 0 y ${_fmt(_max)}.')));
        return;
      }
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Guardar en el aula'),
        content: Text('${_e['alumno'] ?? widget.alumno} · ${_e['tarea'] ?? widget.tarea}\n\n'
            'Calificación: ${cal == null ? '—' : _fmt(cal)} de ${_fmt(_max)}${conRubrica ? ' (por rúbrica)' : ''}\n'
            'Retroalimentación: ${_retro.text.trim().isEmpty ? 'sin texto' : '${_retro.text.trim().length} caracteres'}\n'
            '${_avisar ? 'Moodle le avisará al alumno.' : 'Moodle NO le avisará al alumno.'}'
            '${_e['calificacionActual'] != null ? '\n\nReemplaza la calificación actual (${_e['calificacionActual']}).' : ''}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: cessumRed), onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _guardando = true);
    Map<String, dynamic> d;
    try {
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'entrega_calificar',
                'llave': widget.llave,
                'calificacion': conRubrica ? null : cal,
                'retro': _retro.text.trim(),
                'niveles': _nivel,
                'notificar': _avisar,
              }))
          .timeout(const Duration(seconds: 120));
      d = jsonDecode(r.body) as Map<String, dynamic>;
    } catch (_) {
      d = {'ok': false, 'error': 'La conexión se cortó. Revisa en el aula si la calificación quedó antes de volver a guardar.'};
    }
    if (!mounted) return;
    setState(() => _guardando = false);
    if (d['ok'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: _verde,
          content: Text('Guardado en el aula: ${d['calificacion'] ?? '—'} de ${d['calificacionMaxima'] ?? _fmt(_max)}. La entrega quedó revisada.')));
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: cessumRed, content: Text('${d['error'] ?? 'No se pudo guardar.'}')));
    }
  }

  String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: _barraMarca(context, 'Calificar y retroalimentar', '${_e['alumno'] ?? widget.alumno} · ${_e['tarea'] ?? widget.tarea}'),
      bottomNavigationBar: (_cargando || _error.isNotEmpty) ? null : _barraGuardar(),
      body: _cargando
          ? const CessumSkeletonList(count: 4)
          : _error.isNotEmpty
              ? CessumEmptyState(icon: Icons.cloud_off_rounded, title: 'No se pudo leer la calificación del aula', subtitle: _error)
              : ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
                  if (_e['calificacionActual'] != null)
                    _aviso(Icons.info_outline, 'Ya tiene ${_e['calificacionActual']} de ${_fmt(_max)} en el aula. Guardar la reemplaza.', cessumGold),
                  if (_e['flujoDeCalificacion'] == true)
                    _aviso(Icons.account_tree_outlined, 'La tarea usa flujo de calificación: se guardará como liberada, visible para el alumno.', cessumGold),
                  _tarjeta('Borrador con IA', paso: 1, icono: Icons.auto_awesome, [
                    Text('Propone calificación, niveles de la rúbrica y una retroalimentación formal de un párrafo: lo logrado, lo que faltó '
                        'y hacia dónde seguir. Evalúa sobre la lectura verificada de los archivos, si ya la hiciste.',
                        style: TextStyle(fontSize: 12.5, color: cessumMuted(context), height: 1.4)),
                    if (widget.borradorInicial != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: _verde.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
                        child: Row(children: [
                          Icon(Icons.check_circle_outline, size: 18, color: _verde),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('Ya trajiste la sugerencia que generaste antes de entrar aquí. Puedes ajustarla abajo o pedir otra.',
                                style: TextStyle(fontSize: 12.5, color: _verde, height: 1.35)),
                          ),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 10),
                    // (5-oct-2026) El prompt o la rúbrica del docente para esta tarea.
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _criteriosTxt.isEmpty ? cessumBg(context) : cessumGold.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(children: [
                        Icon(Icons.rule_folder_outlined, size: 20, color: _criteriosTxt.isEmpty ? cessumMuted(context) : cessumGold),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _criteriosTxt.isEmpty ? _textoSinCriterios() : 'Con tus criterios de revisión para esta tarea: ${_resumenCriterios()}',
                            style: const TextStyle(fontSize: 12.5, height: 1.35),
                          ),
                        ),
                        TextButton(
                          onPressed: _pidiendoIa ? null : _editarCriterios,
                          child: Text(_criteriosTxt.isNotEmpty ? 'Editar' : (_critAuto.isNotEmpty ? 'Ver o ajustar' : 'Indicaciones (opcional)')),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(foregroundColor: cessumGold),
                      onPressed: _pidiendoIa ? null : _usarIa,
                      icon: _pidiendoIa
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.auto_awesome, size: 18),
                      label: Text(_pidiendoIa ? 'Generando… (hasta un minuto)' : (_ia == null ? 'Usar el borrador con IA' : 'Generar otro borrador')),
                    ),
                    if (_ia != null) ...[
                      const SizedBox(height: 10),
                      if ((_ia!['sobreLectura'] as num? ?? 0) > 0)
                        Text('Evaluado sobre ${_ia!['sobreLectura']} lectura(s) de archivos'
                            '${(_ia!['lecturaVerificada'] as num? ?? 0) > 0 ? ', ${_ia!['lecturaVerificada']} verificada(s) por ti' : ', sin verificar'}.',
                            style: const TextStyle(fontSize: 12, color: _verde, fontWeight: FontWeight.w600)),
                      for (final f in ((_ia!['fortalezas'] as List?) ?? [])) Text('+ $f', style: const TextStyle(fontSize: 12.5, height: 1.4)),
                      for (final f in ((_ia!['faltantes'] as List?) ?? [])) Text('– $f', style: const TextStyle(fontSize: 12.5, height: 1.4, color: cessumRed)),
                      Text(
                          const {
                                'docente': 'Revisado con tus criterios para esta tarea.',
                                'moodle': 'Revisado con la rúbrica de la tarea en Moodle.',
                                'instruccion': 'Revisado con los criterios que la IA dedujo de la instrucción.',
                              }['${_ia!['fuenteCriterios'] ?? ''}'] ??
                              'Revisado con la consigna de la tarea.',
                          style: const TextStyle(fontSize: 12, color: _verde, fontWeight: FontWeight.w600)),
                      if (_ia!['tareaCerrada'] == true)
                        Text('La tarea ya cerró: la orientación mira a las próximas tareas, sin pedir que se rehaga esta.',
                            style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: cessumMuted(context))),
                    ],
                  ]),
                  if (_rubrica.isNotEmpty)
                    _tarjeta('Rúbrica', paso: 2, icono: Icons.rule_rounded, [
                      for (final c in _rubrica) _criterio(c),
                      const SizedBox(height: 4),
                      Text(_calRubrica == null ? 'Elige un nivel en cada criterio.' : 'Calificación por rúbrica: ${_fmt(_calRubrica!)} de ${_fmt(_max)}',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _calRubrica == null ? cessumMuted(context) : cessumRed)),
                    ])
                  else
                    _tarjeta('Calificación', paso: 2, icono: Icons.grade_outlined, [
                      TextField(
                        controller: _cal,
                        onChanged: (_) => setState(() {}),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(border: const OutlineInputBorder(), labelText: 'De 0 a ${_fmt(_max)}', isDense: true),
                      ),
                    ]),
                  _tarjeta('Retroalimentación para el alumno', paso: 3, icono: Icons.chat_outlined, [
                    TextField(
                      controller: _retro,
                      minLines: 5,
                      maxLines: 14,
                      decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Lo que logró, lo que faltó y, si la tarea sigue abierta, cómo mejorarlo.'),
                    ),
                  ]),
                  _tarjeta('Aviso al alumno', paso: 4, icono: Icons.notifications_outlined, [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeColor: cessumRed,
                      value: _avisar,
                      onChanged: (v) => setState(() => _avisar = v),
                      title: const Text('Que Moodle le avise al alumno', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          'Moodle le manda una notificación de que su tarea fue calificada. '
                          'Esta tarea ${_e['avisaAlAlumno'] == false ? 'NO avisa' : 'avisa'} por omisión.',
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ]),
                ]),
    );
  }

  Widget _aviso(IconData i, String t, Color c) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
        child: Row(children: [Icon(i, color: c, size: 18), const SizedBox(width: 8), Expanded(child: Text(t, style: const TextStyle(fontSize: 12.5)))]),
      );

  Widget _tarjeta(String titulo, List<Widget> hijos, {int paso = 0, IconData icono = Icons.circle}) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 14, offset: const Offset(0, 4))],
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (paso > 0)
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: cessumRed, shape: BoxShape.circle),
                child: Text('$paso', style: CessumType.heading(12.5, color: Colors.white, weight: FontWeight.w900)),
              ),
            if (paso > 0) const SizedBox(width: 10),
            Expanded(child: Text(titulo, style: CessumType.heading(15, color: cessumInk(context), weight: FontWeight.w800))),
            Icon(icono, size: 19, color: cessumGold),
          ]),
          const SizedBox(height: 10),
          ...hijos,
        ]),
      );

  /// (estética) Barra fija abajo: la calificación que se va a guardar, en vivo, y el botón.
  Widget _barraGuardar() {
    final conRubrica = _rubrica.isNotEmpty;
    final cal = conRubrica ? _calRubrica : double.tryParse(_cal.text.trim().replaceAll(',', '.'));
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 14, offset: const Offset(0, -3))],
        ),
        child: Row(children: [
          Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Calificación', style: CessumType.label(11, color: cessumMuted(context))),
            RichText(
              text: TextSpan(children: [
                TextSpan(text: cal == null ? '—' : _fmt(cal), style: CessumType.heading(24, color: cal == null ? CC.muted : cessumRed, weight: FontWeight.w900)),
                TextSpan(text: ' / ${_fmt(_max)}', style: CessumType.body(13, color: cessumMuted(context))),
              ]),
            ),
          ]),
          const SizedBox(width: 14),
          Expanded(
            child: SizedBox(
              height: 50,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: cessumRed, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                onPressed: _guardando ? null : _guardar,
                icon: _guardando
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.cloud_upload_outlined),
                label: Text(_guardando ? 'Guardando en el aula…' : 'Guardar en el aula', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _criterio(Map<String, dynamic> c) {
    final cid = '${c['id']}';
    final niv = ((c['niveles'] as List?) ?? []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
    final sug = (_ia?['porCriterio'] as List?)?.map((x) => Map<String, dynamic>.from(x as Map)).where((m) => '${m['criterioId']}' == cid).toList() ?? [];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${c['criterio']}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final n in niv)
            ChoiceChip(
              selected: _nivel[cid] == (n['id'] as num?)?.toInt(),
              selectedColor: cessumRed.withValues(alpha: 0.15),
              onSelected: (_) => setState(() => _nivel[cid] = (n['id'] as num).toInt()),
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text('${_fmt(((n['puntos'] as num?) ?? 0).toDouble())} · ${n['descripcion']}',
                    maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
              ),
            ),
        ]),
        if (sug.isNotEmpty && '${sug.first['comentario'] ?? ''}'.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('IA: ${sug.first['comentario']}', style: TextStyle(fontSize: 11.5, fontStyle: FontStyle.italic, color: cessumMuted(context))),
          ),
      ]),
    );
  }
}


// =====================================================================
//  R4 (4-oct-2026) — ANOTAR Y DEVOLVER. El PDF o la foto del alumno se
//  abre en un anotador que corre en el navegador del docente (pdf.js lo
//  dibuja, pdf-lib escribe las marcas): resaltador, lápiz, ✓, ✗ y
//  comentarios numerados. El resultado es un PDF nuevo —el original con
//  las marcas y una página «Comentarios del docente»— que se adjunta en
//  Moodle como archivo de retroalimentación de la entrega.
//  Ruta: entrega_retro_archivo (POST).
// =====================================================================

// =====================================================================
//  (5-oct-2026) CRITERIOS DE REVISIÓN DEL DOCENTE. El docente le da a la
//  IA su forma de revisar una tarea: un prompt o una rúbrica pegada. Se
//  guardan POR TAREA: se escriben una vez y valen para todas las entregas
//  de esa tarea. Lo usan «Calificar y retroalimentar» y el borrador de
//  «Revisiones pendientes». Devuelve true si se guardaron cambios.
//  Rutas: entrega_criterios (GET) · entrega_criterios_guardar (POST).
// =====================================================================
const String _kPlantillaRubrica =
    'RÚBRICA\n'
    '1. [Criterio] (0-4 puntos): 4 = …; 2 = …; 0 = …\n'
    '2. [Criterio] (0-3 puntos): 3 = …; 1 = …; 0 = …\n'
    '3. [Criterio] (0-3 puntos): 3 = …; 1 = …; 0 = …\n'
    'Calificación = suma sobre 10.';
const String _kPlantillaPrompt =
    'AL REVISAR ESTA TAREA:\n'
    '· Fíjate en que …\n'
    '· No penalices …\n'
    '· Lo indispensable para aprobar es …\n'
    '· En la retroalimentación, enfatiza …';

Future<bool> editarCriteriosRevision(BuildContext context, String llave, {String tarea = ''}) async {
  final ctrl = TextEditingController();
  String actualizado = '', quien = '', auto = '';
  List<String> rubM = [];
  try {
    final r = await http
        .get(Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'entrega_criterios', 'llave': llave}))
        .timeout(const Duration(seconds: 60));
    final d = jsonDecode(r.body) as Map<String, dynamic>;
    if (d['ok'] == true) {
      ctrl.text = '${d['texto'] ?? ''}';
      actualizado = '${d['actualizado'] ?? ''}';
      quien = '${d['docente'] ?? ''}';
      auto = '${d['criteriosAuto'] ?? ''}';
      rubM = ((d['rubricaMoodle'] as List?) ?? []).map((x) => '$x').toList();
    }
  } catch (_) {}
  if (!context.mounted) return false;
  final guardar = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.rule_folder_outlined, color: cessumGold),
          const SizedBox(width: 8),
          Expanded(child: Text(tarea.isEmpty ? 'Criterios de revisión' : 'Criterios de revisión · $tarea', style: const TextStyle(fontSize: 17))),
        ]),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text(
                'Escribe cómo quieres que la IA revise ESTA tarea: un prompt con tus indicaciones o una rúbrica con criterios y niveles. '
                'Valen para todas las entregas de esta tarea. Complementan la consigna y la rúbrica de Moodle, si la hay.',
                style: TextStyle(fontSize: 12.5, height: 1.45),
              ),
              if (actualizado.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Guardados el $actualizado${quien.isNotEmpty ? ' por $quien' : ''}.', style: TextStyle(fontSize: 11.5, color: cessumMuted(ctx))),
              ],
              // (5-oct-2026) Lo que la IA ya usa sin que el docente escriba nada.
              if (rubM.isNotEmpty || auto.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: cessumGold.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    rubM.isNotEmpty
                        ? 'Esta tarea ya tiene rúbrica en Moodle (${rubM.join(' · ')}). La IA la usa sola: escribe aquí solo si quieres agregar indicaciones.'
                        : 'La IA ya dedujo estos criterios de la instrucción y los usa para toda la tarea:\n\n$auto',
                    style: const TextStyle(fontSize: 12, height: 1.45),
                  ),
                ),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (auto.isNotEmpty)
                  ActionChip(
                    avatar: const Icon(Icons.auto_awesome, size: 16),
                    label: const Text('Partir de los criterios deducidos'),
                    onPressed: () => setD(() => ctrl.text = ctrl.text.trim().isEmpty ? auto : '${ctrl.text.trim()}\n\n$auto'),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.table_rows_outlined, size: 16),
                  label: const Text('Plantilla de rúbrica'),
                  onPressed: () => setD(() => ctrl.text = ctrl.text.trim().isEmpty ? _kPlantillaRubrica : '${ctrl.text.trim()}\n\n$_kPlantillaRubrica'),
                ),
                ActionChip(
                  avatar: const Icon(Icons.edit_note, size: 16),
                  label: const Text('Plantilla de indicaciones'),
                  onPressed: () => setD(() => ctrl.text = ctrl.text.trim().isEmpty ? _kPlantillaPrompt : '${ctrl.text.trim()}\n\n$_kPlantillaPrompt'),
                ),
              ]),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                minLines: 8,
                maxLines: 18,
                maxLength: 8000,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Pega aquí tu rúbrica o escribe tus indicaciones de revisión…',
                ),
              ),
              Text('Si lo dejas vacío y guardas, se borran y la IA revisa solo con la consigna y la rúbrica de Moodle.',
                  style: TextStyle(fontSize: 11.5, color: cessumMuted(ctx))),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('Guardar criterios'),
          ),
        ],
      ),
    ),
  );
  if (guardar != true) {
    ctrl.dispose();
    return false;
  }
  bool ok = false;
  String msg;
  try {
    final r = await http
        .post(Uri.parse(guardianUrl),
            headers: {'Content-Type': 'text/plain;charset=utf-8'},
            body: jsonEncode({'accion': 'entrega_criterios_guardar', 'llave': llave, 'texto': ctrl.text.trim()}))
        .timeout(const Duration(seconds: 60));
    final d = jsonDecode(r.body) as Map<String, dynamic>;
    ok = d['ok'] == true;
    msg = ok
        ? (d['guardado'] == true ? 'Criterios guardados para todas las entregas de esta tarea.' : 'Criterios borrados para esta tarea.')
        : '${d['error'] ?? 'No se pudieron guardar.'}';
  } catch (_) {
    msg = 'No se pudo conectar. Intenta de nuevo.';
  }
  ctrl.dispose();
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: ok ? const Color(0xFF1E7B34) : cessumRed, content: Text(msg)));
  }
  return ok;
}

// =====================================================================
//  (4-oct-2026, estética) ENCABEZADO DE MARCA de la Mesa de revisión: el
//  mismo lenguaje que CessumAppBar (blanco, rojo, franja rojo→dorado) con
//  un subtítulo (alumno · tarea) y, si hace falta, pestañas.
// =====================================================================
PreferredSizeWidget _barraMarca(BuildContext context, String titulo, String subtitulo,
    {List<Widget>? actions, PreferredSizeWidget? pestanas}) {
  final alto = (pestanas?.preferredSize.height ?? 0) + 3;
  return AppBar(
    backgroundColor: Colors.white,
    foregroundColor: cessumRed,
    surfaceTintColor: Colors.white,
    elevation: 1,
    titleSpacing: 4,
    title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(titulo, style: CessumType.heading(16.5, color: cessumRed, weight: FontWeight.w800)),
      if (subtitulo.trim().isNotEmpty)
        Text(subtitulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: CessumType.body(12, color: CC.muted)),
    ]),
    actions: actions,
    bottom: PreferredSize(
      preferredSize: Size.fromHeight(alto),
      child: Column(children: [
        if (pestanas != null) pestanas,
        Container(height: 3, decoration: const BoxDecoration(gradient: LinearGradient(colors: [cessumRed, cessumGold]))),
      ]),
    ),
  );
}

const String _kPdfJs = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.min.js';
const String _kPdfJsWorker = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js';
const String _kPdfLib = 'https://cdnjs.cloudflare.com/ajax/libs/pdf-lib/1.17.1/pdf-lib.min.js';

class AnotarEntregaScreen extends StatefulWidget {
  final String llave;
  final String base64;
  final String mime;
  final String nombre;
  final String titulo;
  const AnotarEntregaScreen({super.key, required this.llave, required this.base64, required this.mime, required this.nombre, this.titulo = ''});
  @override
  State<AnotarEntregaScreen> createState() => _AnotarEntregaScreenState();
}

class _AnotarEntregaScreenState extends State<AnotarEntregaScreen> {
  late final String _url;
  dynamic _escucha;
  bool _subiendo = false;

  @override
  void initState() {
    super.initState();
    final html0 = _kAnotadorHtml
        .replaceAll('__PDFJSWORKER__', _kPdfJsWorker)
        .replaceAll('__PDFJS__', _kPdfJs)
        .replaceAll('__PDFLIB__', _kPdfLib)
        .replaceAll('__MIME__', widget.mime)
        .replaceAll('__TITULO__', jsonEncode(widget.titulo))
        .replaceAll('__DATOS__', widget.base64);
    _url = html.Url.createObjectUrlFromBlob(html.Blob([html0], 'text/html'));
    _escucha = html.window.onMessage.listen(_mensaje);
  }

  @override
  void dispose() {
    try {
      (_escucha as dynamic).cancel();
    } catch (_) {}
    try {
      html.Url.revokeObjectUrl(_url);
    } catch (_) {}
    super.dispose();
  }

  String get _nombreSalida {
    final base = widget.nombre.contains('.') ? widget.nombre.substring(0, widget.nombre.lastIndexOf('.')) : widget.nombre;
    return 'Retroalimentacion_$base.pdf';
  }

  Future<void> _mensaje(html.MessageEvent e) async {
    Map<String, dynamic> d;
    try {
      d = Map<String, dynamic>.from(jsonDecode('${e.data}') as Map);
    } catch (_) {
      return;
    }
    if (d['tipo'] == 'cessum-anotador-error') {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: cessumRed,
            content: Text(d['error'] == 'librerías' ? 'No se pudieron cargar las herramientas del anotador. Revisa la conexión.' : 'El anotador tuvo un problema: ${d['error']}')));
      }
      return;
    }
    if (d['tipo'] != 'cessum-anotado' || !mounted) return;
    final b64 = '${d['base64'] ?? ''}';
    final kb = ((d['bytes'] as num?) ?? 0) / 1024;
    final eleccion = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('PDF anotado listo'),
        content: Text('${d['marcas']} marca(s) y ${d['notas']} comentario(s) · ${kb.toStringAsFixed(0)} KB.\n\n'
            'Se adjuntará en el aula como «$_nombreSalida», en la retroalimentación de esta entrega. El alumno lo verá junto a su calificación.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'seguir'), child: const Text('Seguir anotando')),
          OutlinedButton.icon(onPressed: () => Navigator.pop(ctx, 'descargar'), icon: const Icon(Icons.download, size: 17), label: const Text('Solo descargar')),
          FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: cessumRed),
              onPressed: () => Navigator.pop(ctx, 'adjuntar'),
              icon: const Icon(Icons.attach_file, size: 17),
              label: const Text('Adjuntar en el aula')),
        ],
      ),
    );
    if (eleccion == 'descargar' || eleccion == 'adjuntar') {
      // Siempre queda una copia en la computadora del docente.
      final u = html.Url.createObjectUrlFromBlob(html.Blob([base64Decode(b64)], 'application/pdf'));
      html.AnchorElement(href: u)
        ..download = _nombreSalida
        ..click();
    }
    if (eleccion != 'adjuntar' || !mounted) return;
    setState(() => _subiendo = true);
    Map<String, dynamic> r;
    try {
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'entrega_retro_archivo',
                'llave': widget.llave,
                'nombre': _nombreSalida,
                'datos_b64': b64,
                'marcas': d['marcas'],
                'notas': d['notas'],
              }))
          .timeout(const Duration(seconds: 150));
      r = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      r = {'ok': false, 'error': 'La conexión se cortó. La copia quedó descargada en tu computadora.'};
    }
    if (!mounted) return;
    setState(() => _subiendo = false);
    if (r['ok'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: const Color(0xFF1E7B34),
          content: Text('Adjuntado en el aula: ${r['archivo']}${r['seActivoEnLaTarea'] == true ? ' (se activó la retroalimentación con archivo en esta tarea)' : ''}.')));
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: cessumRed, content: Text('${r['error'] ?? 'No se pudo adjuntar.'}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _barraMarca(context, 'Anotar y devolver', widget.nombre),
      body: Stack(children: [
        Positioned.fill(child: _Iframe(src: _url)),
        if (_subiendo)
          Container(
            color: Colors.black38,
            child: const Center(
                child: Card(
                    child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          CircularProgressIndicator(color: cessumRed),
                          SizedBox(width: 14),
                          Text('Adjuntando en el aula…'),
                        ])))),
          ),
      ]),
    );
  }
}

const String _kAnotadorHtml = r'''<!doctype html>
<html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<link href="https://fonts.googleapis.com/css2?family=Montserrat:wght@400;600;700;800&display=swap" rel="stylesheet">
<script src="__PDFJS__"></script>
<script src="__PDFLIB__"></script>
<style>
:root{--g:#C8202F;--v:#8E1620;--go:#B8842C;--t:#1F1A17;--h:#F5F1E8;--m:#6B6257;--c:#E6DCCB}
*{box-sizing:border-box}html,body{margin:0;height:100%}
body{font-family:Montserrat,Arial,sans-serif;background:#4A3F38;color:var(--t);display:flex;flex-direction:column}
#barra{flex:0 0 auto;display:flex;align-items:center;gap:10px;padding:8px 12px;background:#fff;box-shadow:0 2px 10px rgba(0,0,0,.18);flex-wrap:wrap;position:sticky;top:0;z-index:5;border-bottom:3px solid transparent;border-image:linear-gradient(90deg,#C8202F,#B8842C) 1}
#barra .grupo{display:flex;gap:3px;background:#F5F1E8;border-radius:12px;padding:3px}
#barra button{border:0;background:transparent;color:#4A3F38;border-radius:9px;padding:7px 10px;font:inherit;font-size:12.5px;font-weight:700;cursor:pointer;display:flex;align-items:center;gap:6px;transition:background .15s,color .15s}
#barra button:hover{background:#fff}
#barra button.on{background:var(--v);color:#fff;box-shadow:0 2px 6px rgba(142,22,32,.35)}
#barra button.ok:not(.on){color:#1E7B34}#barra button.mal:not(.on){color:#C8202F}
#barra button:disabled{opacity:.45;cursor:default}
#barra .esp{flex:1}
#cuenta{font-size:12px;color:var(--m);font-weight:600}
#terminar{background:var(--g)!important;color:#fff!important;padding:9px 14px!important;border-radius:11px!important;box-shadow:0 3px 10px rgba(200,32,47,.35)}
#terminar:hover{background:var(--v)!important}
@media (max-width:700px){#barra button span{display:none}#cuenta{display:none}}
#paginas{flex:1;overflow:auto;padding:18px 10px 60px;display:flex;flex-direction:column;align-items:center;gap:16px}
.pag{position:relative;box-shadow:0 6px 24px rgba(0,0,0,.35);background:#fff}
.pag canvas{display:block}
.pag .capa{position:absolute;left:0;top:0;touch-action:none}
.pag .num{position:absolute;right:-2px;top:-22px;color:#E8DCCB;font-size:11px;font-weight:700}
.mano .capa{pointer-events:none}
#modal{position:fixed;inset:0;background:rgba(20,14,10,.55);display:none;align-items:center;justify-content:center;z-index:20}
#modal.ver{display:flex}
#modal .caja{background:#fff;border-radius:14px;padding:16px;width:min(460px,92vw);box-shadow:0 20px 60px rgba(0,0,0,.4)}
#modal h4{margin:0 0 8px;font-size:13px;letter-spacing:1.5px;text-transform:uppercase;color:var(--g)}
#modal textarea{width:100%;min-height:110px;border:1.5px solid var(--c);border-radius:10px;padding:10px;font:inherit;font-size:14px;resize:vertical}
#modal .acc{display:flex;gap:8px;justify-content:flex-end;margin-top:10px}
#modal .acc button{border:0;border-radius:10px;padding:9px 14px;font:inherit;font-weight:700;cursor:pointer}
#estado{position:fixed;left:50%;bottom:16px;transform:translateX(-50%);background:var(--t);color:#fff;padding:10px 16px;border-radius:12px;font-size:13px;display:none;z-index:30;max-width:90vw;text-align:center}
#estado.ver{display:block}
</style></head><body>
<div id="barra">
  <div class="grupo">
    <button data-h="mano" title="Mover y desplazarse"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 9l-3 3 3 3M9 5l3-3 3 3M15 19l-3 3-3-3M19 9l3 3-3 3M2 12h20M12 2v20"/></svg><span>Mover</span></button>
    <button data-h="resaltar" title="Resaltar"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 11l-6 6v3h9l3-3"/><path d="M22 12l-4.6 4.6a2 2 0 0 1-2.8 0l-5.2-5.2a2 2 0 0 1 0-2.8L14 4"/></svg><span>Resaltar</span></button>
    <button data-h="lapiz" class="on" title="Lápiz rojo"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 3a2.85 2.85 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z"/></svg><span>Lápiz</span></button>
    <button data-h="check" class="ok" title="Marca de acierto"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 6 9 17l-5-5"/></svg></button>
    <button data-h="cruz" class="mal" title="Marca de error"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18M6 6l12 12"/></svg></button>
    <button data-h="nota" title="Comentario numerado"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/><path d="M8 9h8M8 13h5"/></svg><span>Comentario</span></button>
  </div>
  <div class="grupo">
    <button id="deshacer" title="Deshacer"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 7v6h6"/><path d="M21 17a9 9 0 0 0-9-9 9 9 0 0 0-6 2.3L3 13"/></svg></button>
    <button id="menos" title="Alejar"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3M8 11h6"/></svg></button>
    <button id="mas" title="Acercar"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3M8 11h6M11 8v6"/></svg></button>
  </div>
  <span class="esp"></span>
  <span id="cuenta">0 marcas · 0 comentarios</span>
  <button id="terminar"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 11.1V12a10 10 0 1 1-5.9-9.1"/><path d="m22 4-10 10-3-3"/></svg><span>Terminar y devolver</span></button>
</div>
<div id="paginas"></div>
<div id="modal"><div class="caja"><h4>Comentario <span id="mnum"></span></h4>
  <textarea id="mtexto" placeholder="Escribe el comentario para el alumno…"></textarea>
  <div class="acc"><button id="mcancel" style="background:#EFE9DC">Cancelar</button><button id="mok" style="background:#C8202F;color:#fff">Poner comentario</button></div></div></div>
<div id="estado"></div>
<script>
(function () {
  var DATOS = "__DATOS__", MIME = "__MIME__", TITULO = __TITULO__;
  var avisa = function (t, ms) { var e = document.getElementById('estado'); e.textContent = t; e.classList.add('ver'); if (ms) setTimeout(function () { e.classList.remove('ver'); }, ms); };
  var manda = function (o) { try { window.parent.postMessage(JSON.stringify(o), '*'); } catch (e) {} };
  if (typeof pdfjsLib === 'undefined' || typeof PDFLib === 'undefined') {
    avisa('No se pudieron cargar las herramientas del anotador. Revisa tu conexión y vuelve a abrirlo.');
    manda({ tipo: 'cessum-anotador-error', error: 'librerías' }); return;
  }
  /* El «trabajador» de pdf.js viene de otro dominio: se descarga y se crea local (si falla, pdf.js trabaja en modo simple). */
  var listoTrabajador = fetch("__PDFJSWORKER__").then(function (r) { if (!r.ok) throw 0; return r.blob(); })
    .then(function (bl) { pdfjsLib.GlobalWorkerOptions.workerSrc = URL.createObjectURL(bl); })
    .catch(function () { pdfjsLib.GlobalWorkerOptions.workerSrc = "__PDFJSWORKER__"; });
  var bin = atob(DATOS), BYTES = new Uint8Array(bin.length);
  for (var i = 0; i < bin.length; i++) BYTES[i] = bin.charCodeAt(i);
  var ES_PDF = MIME.indexOf('pdf') >= 0;
  var herr = 'lapiz', escala = 1.35, paginas = [], historial = [], imgDatos = null;
  var cont = document.getElementById('paginas');

  /* ── Las marcas se guardan en coordenadas relativas (0 a 1) a la página tal como se ve: sobreviven al zoom ── */
  function numeroNotas() { var n = 0, m = new Map(); paginas.forEach(function (p) { p.ops.forEach(function (o) { if (o.t === 'nota') m.set(o, ++n); }); }); return m; }
  function cuenta() {
    var mk = 0, nt = 0; paginas.forEach(function (p) { p.ops.forEach(function (o) { if (o.t === 'nota') nt++; else mk++; }); });
    document.getElementById('cuenta').textContent = mk + ' marca' + (mk === 1 ? '' : 's') + ' · ' + nt + ' comentario' + (nt === 1 ? '' : 's');
    return { marcas: mk, notas: nt };
  }
  function dibuja(p) {
    var c = p.ctx, W = p.capa.width, H = p.capa.height, nums = numeroNotas();
    c.clearRect(0, 0, W, H);
    p.ops.forEach(function (o) {
      if (o.t === 'trazo') {
        c.save(); c.globalAlpha = o.alfa; c.strokeStyle = o.c; c.lineWidth = o.a * W; c.lineCap = 'round'; c.lineJoin = 'round';
        c.beginPath(); o.p.forEach(function (q, k) { if (k) c.lineTo(q[0] * W, q[1] * H); else c.moveTo(q[0] * W, q[1] * H); });
        if (o.p.length === 1) c.lineTo(o.p[0][0] * W + 0.1, o.p[0][1] * H); c.stroke(); c.restore();
      } else if (o.t === 'check' || o.t === 'cruz') {
        var s = 0.022 * W, x = o.x * W, y = o.y * H; c.save(); c.lineWidth = Math.max(2, 0.0045 * W); c.lineCap = 'round';
        c.strokeStyle = o.t === 'check' ? '#1E7B34' : '#C8202F'; c.beginPath();
        if (o.t === 'check') { c.moveTo(x - s, y); c.lineTo(x - s * 0.3, y + s * 0.8); c.lineTo(x + s * 1.1, y - s * 0.9); }
        else { c.moveTo(x - s, y - s); c.lineTo(x + s, y + s); c.moveTo(x + s, y - s); c.lineTo(x - s, y + s); }
        c.stroke(); c.restore();
      } else if (o.t === 'nota') {
        var r = 0.017 * W, nx = o.x * W, ny = o.y * H; c.save(); c.fillStyle = '#C8202F'; c.beginPath(); c.arc(nx, ny, r, 0, Math.PI * 2); c.fill();
        c.fillStyle = '#fff'; c.font = 'bold ' + Math.round(r * 1.15) + 'px Montserrat, Arial'; c.textAlign = 'center'; c.textBaseline = 'middle';
        c.fillText(String(nums.get(o)), nx, ny + 0.5); c.restore();
      }
    });
  }
  function todas() { paginas.forEach(dibuja); cuenta(); }

  function preparaCapa(p) {
    var capa = p.capa, actual = null;
    var pos = function (e) { var r = capa.getBoundingClientRect(); return [(e.clientX - r.left) / r.width, (e.clientY - r.top) / r.height]; };
    capa.addEventListener('pointerdown', function (e) {
      if (herr === 'mano') return;
      e.preventDefault(); var q = pos(e);
      if (herr === 'lapiz' || herr === 'resaltar') {
        actual = herr === 'lapiz' ? { t: 'trazo', c: '#C8202F', a: 0.0035, alfa: 0.95, p: [q] } : { t: 'trazo', c: '#F7D417', a: 0.022, alfa: 0.38, p: [q] };
        p.ops.push(actual); capa.setPointerCapture(e.pointerId); dibuja(p);
      } else if (herr === 'check' || herr === 'cruz') {
        var o = { t: herr, x: q[0], y: q[1] }; p.ops.push(o); historial.push({ p: p, o: o }); todas();
      } else if (herr === 'nota') { abreNota(p, q); }
    });
    capa.addEventListener('pointermove', function (e) { if (!actual) return; actual.p.push(pos(e)); dibuja(p); });
    var fin = function () { if (actual) { historial.push({ p: p, o: actual }); actual = null; cuenta(); } };
    capa.addEventListener('pointerup', fin); capa.addEventListener('pointercancel', fin);
  }

  /* Comentario numerado */
  var notaPend = null;
  function abreNota(p, q) {
    notaPend = { p: p, q: q }; var nt = 0; paginas.forEach(function (x) { x.ops.forEach(function (o) { if (o.t === 'nota') nt++; }); });
    document.getElementById('mnum').textContent = '#' + (nt + 1); document.getElementById('mtexto').value = '';
    document.getElementById('modal').classList.add('ver'); setTimeout(function () { document.getElementById('mtexto').focus(); }, 30);
  }
  document.getElementById('mcancel').onclick = function () { notaPend = null; document.getElementById('modal').classList.remove('ver'); };
  document.getElementById('mok').onclick = function () {
    var t = document.getElementById('mtexto').value.trim(); if (!t || !notaPend) return;
    var o = { t: 'nota', x: notaPend.q[0], y: notaPend.q[1], txt: t }; notaPend.p.ops.push(o); historial.push({ p: notaPend.p, o: o });
    notaPend = null; document.getElementById('modal').classList.remove('ver'); todas();
  };

  /* Herramientas */
  [].slice.call(document.querySelectorAll('[data-h]')).forEach(function (b) {
    b.onclick = function () { herr = b.getAttribute('data-h'); [].slice.call(document.querySelectorAll('[data-h]')).forEach(function (x) { x.classList.toggle('on', x === b); });
      document.body.classList.toggle('mano', herr === 'mano'); };
  });
  document.getElementById('deshacer').onclick = function () {
    var h = historial.pop(); if (!h) return; var k = h.p.ops.indexOf(h.o); if (k >= 0) h.p.ops.splice(k, 1); todas();
  };
  document.getElementById('mas').onclick = function () { escala = Math.min(3, escala + 0.25); pinta(); };
  document.getElementById('menos').onclick = function () { escala = Math.max(0.6, escala - 0.25); pinta(); };

  /* ── Pintar el documento ── */
  var pdfDoc = null, imgEl = null;
  function nuevaPagina(i, w, h) {
    var p = paginas[i];
    if (!p) { p = { ops: [] }; paginas[i] = p; }
    var wrap = document.createElement('div'); wrap.className = 'pag'; wrap.style.width = w + 'px'; wrap.style.height = h + 'px';
    var base = document.createElement('canvas'), capa = document.createElement('canvas'), dpr = window.devicePixelRatio || 1;
    [base, capa].forEach(function (c) { c.width = Math.round(w * dpr); c.height = Math.round(h * dpr); c.style.width = w + 'px'; c.style.height = h + 'px'; });
    capa.className = 'capa'; var num = document.createElement('span'); num.className = 'num'; num.textContent = 'Página ' + (i + 1);
    wrap.appendChild(base); wrap.appendChild(capa); wrap.appendChild(num); cont.appendChild(wrap);
    p.capa = capa; p.ctx = capa.getContext('2d'); p.base = base; p.dpr = dpr;
    preparaCapa(p);
    return p;
  }
  function pinta() {
    cont.innerHTML = '';
    if (pdfDoc) {
      var cadena = Promise.resolve();
      for (var i = 1; i <= pdfDoc.numPages; i++) (function (n) {
        cadena = cadena.then(function () { return pdfDoc.getPage(n); }).then(function (pg) {
          var vp = pg.getViewport({ scale: escala }), p = nuevaPagina(n - 1, Math.round(vp.width), Math.round(vp.height));
          var vp2 = pg.getViewport({ scale: escala * p.dpr });
          return pg.render({ canvasContext: p.base.getContext('2d'), viewport: vp2 }).promise.then(function () { dibuja(p); });
        });
      })(i);
      cadena.then(function () { cuenta(); avisa('Listo para anotar. Elige una herramienta arriba.', 2600); });
    } else if (imgEl) {
      var maxW = Math.min(1100, cont.clientWidth - 30) * (escala / 1.35), w = Math.round(Math.min(maxW, imgEl.naturalWidth)), h = Math.round(w * imgEl.naturalHeight / imgEl.naturalWidth);
      var p = nuevaPagina(0, w, h), c = p.base.getContext('2d'); c.drawImage(imgEl, 0, 0, p.base.width, p.base.height); dibuja(p); cuenta();
    }
  }
  avisa('Abriendo el documento…');
  if (ES_PDF) {
    listoTrabajador.then(function () { return pdfjsLib.getDocument({ data: BYTES.slice() }).promise; }).then(function (d) { pdfDoc = d; pinta(); })
      .catch(function () { avisa('No se pudo abrir el PDF (¿está protegido o dañado?).'); manda({ tipo: 'cessum-anotador-error', error: 'pdf' }); });
  } else {
    imgEl = new Image(); imgEl.onload = function () { pinta(); avisa('Listo para anotar.', 2000); };
    imgEl.onerror = function () { avisa('No se pudo abrir la imagen.'); manda({ tipo: 'cessum-anotador-error', error: 'imagen' }); };
    imgEl.src = 'data:' + MIME + ';base64,' + DATOS;
  }

  /* ── Generar el PDF anotado: el original + las marcas + una página «Comentarios del docente» ── */
  var limpio = function (t) { return String(t || '').replace(/[\u2018\u2019]/g, "'").replace(/[\u201C\u201D]/g, '"').replace(/[\u2013\u2014]/g, '-').replace(/\u2026/g, '...').replace(/[^\x09\x0A\x0D\x20-\x7E\xA0-\xFF]/g, '?'); };
  function aPdf(p, W, H, rot, u, v) {
    if (rot === 90) return { x: v * W, y: u * H };
    if (rot === 180) return { x: (1 - u) * W, y: v * H };
    if (rot === 270) return { x: (1 - v) * W, y: (1 - u) * H };
    return { x: u * W, y: (1 - v) * H };
  }
  function partir(texto, fuente, tam, ancho) {
    var lineas = []; String(texto).split(/\n/).forEach(function (par) {
      var pal = par.split(/\s+/), l = '';
      pal.forEach(function (w) { var prueba = l ? l + ' ' + w : w; if (fuente.widthOfTextAtSize(prueba, tam) > ancho && l) { lineas.push(l); l = w; } else l = prueba; });
      lineas.push(l);
    });
    return lineas;
  }
  document.getElementById('terminar').onclick = async function () {
    var c = cuenta(); if (!c.marcas && !c.notas) { avisa('Todavía no hay marcas ni comentarios.', 2500); return; }
    var btn = this; btn.disabled = true; avisa('Generando el PDF anotado…');
    try {
      var L = PDFLib, doc;
      if (ES_PDF) doc = await L.PDFDocument.load(BYTES, { ignoreEncryption: true });
      else {
        doc = await L.PDFDocument.create();
        var cv = document.createElement('canvas'); cv.width = imgEl.naturalWidth; cv.height = imgEl.naturalHeight; cv.getContext('2d').drawImage(imgEl, 0, 0);
        var png = await doc.embedPng(cv.toDataURL('image/png'));
        var esc = Math.min(1, 595 / png.width * 1.4), pw = png.width * esc * 0.75, ph = png.height * esc * 0.75;
        doc.addPage([pw, ph]).drawImage(png, { x: 0, y: 0, width: pw, height: ph });
      }
      var f = await doc.embedFont(L.StandardFonts.Helvetica), fb = await doc.embedFont(L.StandardFonts.HelveticaBold);
      var rojo = L.rgb(0.784, 0.125, 0.184), verde = L.rgb(0.118, 0.482, 0.204), amarillo = L.rgb(0.97, 0.83, 0.09);
      var pags = doc.getPages(), nums = numeroNotas(), notas = [];
      paginas.forEach(function (p, i) {
        var pg = pags[i]; if (!pg) return;
        var sz = pg.getSize(), W = sz.width, H = sz.height, rot = ((pg.getRotation().angle % 360) + 360) % 360, Wv = (rot === 90 || rot === 270) ? H : W;
        p.ops.forEach(function (o) {
          if (o.t === 'trazo') {
            for (var k = 1; k < Math.max(2, o.p.length); k++) {
              var a = aPdf(p, W, H, rot, o.p[k - 1][0], o.p[k - 1][1]), b = aPdf(p, W, H, rot, (o.p[k] || o.p[k - 1])[0] + (o.p[k] ? 0 : 0.0005), (o.p[k] || o.p[k - 1])[1]);
              pg.drawLine({ start: a, end: b, thickness: o.a * Wv, color: o.c === '#C8202F' ? rojo : amarillo, opacity: o.alfa, lineCap: L.LineCapStyle.Round });
            }
          } else if (o.t === 'check' || o.t === 'cruz') {
            var s = 0.022, segs = o.t === 'check' ? [[[-s, 0], [-s * 0.3, s * 0.8]], [[-s * 0.3, s * 0.8], [s * 1.1, -s * 0.9]]] : [[[-s, -s], [s, s]], [[s, -s], [-s, s]]];
            segs.forEach(function (sg) {
              pg.drawLine({ start: aPdf(p, W, H, rot, o.x + sg[0][0], o.y + sg[0][1] * (Wv / ((rot === 90 || rot === 270) ? W : H))),
                end: aPdf(p, W, H, rot, o.x + sg[1][0], o.y + sg[1][1] * (Wv / ((rot === 90 || rot === 270) ? W : H))),
                thickness: Math.max(1.5, 0.0045 * Wv), color: o.t === 'check' ? verde : rojo, lineCap: L.LineCapStyle.Round });
            });
          } else if (o.t === 'nota') {
            var n = nums.get(o), cpt = aPdf(p, W, H, rot, o.x, o.y), r = 0.017 * Wv, tx = String(n), ts = r * 1.15;
            pg.drawCircle({ x: cpt.x, y: cpt.y, size: r, color: rojo });
            /* El número, centrado en el círculo también en páginas giradas: el desplazamiento se gira con la página. */
            var dx = -fb.widthOfTextAtSize(tx, ts) / 2, dy = -ts * 0.35, th = rot * Math.PI / 180;
            pg.drawText(tx, { x: cpt.x + dx * Math.cos(th) - dy * Math.sin(th), y: cpt.y + dx * Math.sin(th) + dy * Math.cos(th), size: ts, font: fb, color: L.rgb(1, 1, 1), rotate: L.degrees(rot) });
            notas.push({ n: n, pag: i + 1, txt: o.txt });
          }
        });
      });
      if (notas.length) {
        notas.sort(function (a, b) { return a.n - b.n; });
        var PW = 595, PH = 842, M = 54, pg2 = doc.addPage([PW, PH]), y = PH - M;
        var cabeza = function (pg) { pg.drawRectangle({ x: 0, y: PH - 8, width: PW, height: 8, color: rojo }); };
        cabeza(pg2);
        pg2.drawText('Comentarios del docente', { x: M, y: y - 6, size: 18, font: fb, color: L.rgb(0.12, 0.10, 0.09) }); y -= 28;
        if (TITULO) { partir(limpio(TITULO), f, 10.5, PW - 2 * M).forEach(function (l) { pg2.drawText(l, { x: M, y: y, size: 10.5, font: f, color: L.rgb(0.42, 0.38, 0.34) }); y -= 14; }); }
        y -= 10;
        notas.forEach(function (nt) {
          var ls = partir(limpio(nt.txt), f, 11.5, PW - 2 * M - 34);
          if (y - (ls.length * 15 + 12) < M) { pg2 = doc.addPage([PW, PH]); cabeza(pg2); y = PH - M; }
          pg2.drawCircle({ x: M + 10, y: y - 4, size: 10, color: rojo });
          var tn = String(nt.n); pg2.drawText(tn, { x: M + 10 - fb.widthOfTextAtSize(tn, 10) / 2, y: y - 7.5, size: 10, font: fb, color: L.rgb(1, 1, 1) });
          pg2.drawText('Página ' + nt.pag, { x: M + 30, y: y - 8, size: 9, font: fb, color: L.rgb(0.72, 0.52, 0.17) }); y -= 22;
          ls.forEach(function (l) { pg2.drawText(l, { x: M + 30, y: y, size: 11.5, font: f, color: L.rgb(0.12, 0.10, 0.09) }); y -= 15; });
          y -= 10;
        });
      }
      var out = await doc.save(), s = '', TROZO = 0x8000;
      for (var k = 0; k < out.length; k += TROZO) s += String.fromCharCode.apply(null, out.subarray(k, k + TROZO));
      manda({ tipo: 'cessum-anotado', base64: btoa(s), marcas: c.marcas, notas: c.notas, bytes: out.length });
      avisa('PDF anotado listo.', 2500);
    } catch (e) {
      avisa('No se pudo generar el PDF: ' + (e && e.message ? e.message : e)); manda({ tipo: 'cessum-anotador-error', error: String(e && e.message || e) });
    }
    btn.disabled = false;
  };
})();
</script>
</body></html>
''';
