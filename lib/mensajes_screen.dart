// MENSAJERÍA ALUMNO ↔ DOCENTE (ago-2026)
//
// La misma pantalla sirve a los dos: el backend decide, con el correo de la
// sesión, si eres docente o alumno y con quién puedes hablar. No hay dos
// versiones que mantener ni un rol que pasar desde aquí.
//
// Por qué existe: para dejar de repartir números de celular. La conversación
// académica queda junto a la materia, con fecha y sin exponer el teléfono de
// nadie.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';

class MensajesScreen extends StatefulWidget {
  const MensajesScreen({super.key});

  @override
  State<MensajesScreen> createState() => _MensajesScreenState();
}

class _MensajesScreenState extends State<MensajesScreen> {
  String _correo = '';
  String _rol = '';
  List<Map<String, dynamic>> _hilos = [];
  bool _cargando = true;
  String? _error;
  String _filtro = '';

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
      final c = (await SessionStore.validEmail()) ?? '';
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'mensajes_hilos',
        'correo': c,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final d = jsonDecode(resp.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _correo = c;
        _rol = '${d['rol'] ?? ''}';
        _hilos = ((d['hilos'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudieron cargar tus conversaciones.';
      });
    }
  }

  static String _n(String s) {
    var t = s.toLowerCase().trim();
    const ac = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ñ': 'n'};
    ac.forEach((k, v) => t = t.replaceAll(k, v));
    return t;
  }

  List<Map<String, dynamic>> get _visibles {
    final q = _n(_filtro);
    if (q.isEmpty) return _hilos;
    return _hilos.where((h) {
      final heno = _n('${h['conNombre']} ${h['materia']} ${h['grupo']}');
      return heno.contains(q);
    }).toList();
  }

  int get _sinLeerTotal => _hilos.fold<int>(
      0, (a, h) => a + ((h['sinLeer'] is num) ? (h['sinLeer'] as num).toInt() : 0));

  @override
  Widget build(BuildContext context) {
    final vis = _visibles;
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        // (22-sep) El mismo chat, con el nombre de quien lo usa: el alumno
        // entra a «Chat con docente» y el profesor a «Chat con alumno».
        title: Text(_rol == 'docente' ? 'Chat con alumno' : 'Chat con docente'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!),
                    const SizedBox(height: 8),
                    TextButton(
                        onPressed: _cargar, child: const Text('Reintentar')),
                  ]),
                )
              : Column(children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    color: cessumGold.withValues(alpha: 0.10),
                    child: Text(
                        _rol == 'docente'
                            ? 'Aquí te escriben tus alumnos de las materias que estás '
                                'impartiendo. Todo queda registrado junto a la materia, '
                                'y nadie necesita tu número personal.'
                            : 'Escríbele a tus profesores desde aquí. La conversación '
                                'queda junto a tu materia, con fecha, y no necesitas '
                                'su número personal.',
                        style: TextStyle(
                            fontSize: 12, height: 1.45, color: cessumInk(context))),
                  ),
                  if (_hilos.length > 4)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: TextField(
                        onChanged: (v) => setState(() => _filtro = v),
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: 'Buscar por nombre o materia…',
                          prefixIcon: Icon(Icons.search, size: 20),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  if (_sinLeerTotal > 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('$_sinLeerTotal mensaje(s) sin leer',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFC62828))),
                      ),
                    ),
                  Expanded(
                    child: vis.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(28),
                              child: Text(
                                  _hilos.isEmpty
                                      ? 'Todavía no hay materias que te vinculen '
                                          'con alguien. Aquí aparecen las que estás '
                                          'cursando y las que terminaron en los '
                                          'últimos treinta días.'
                                      : 'Nada coincide con «$_filtro».',
                                  textAlign: TextAlign.center,
                                  style:
                                      TextStyle(color: cessumMuted(context))),
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.all(16),
                            children: _seccionadas(vis),
                          ),
                  ),
                ]),
    );
  }

  /* (18-sep) DOS SECCIONES: EN CURSO Y RECIÉN CONCLUIDAS.
     El backend marca con esAnterior las materias que terminaron dentro de los
     últimos treinta días. Antes se mezclaban con las vigentes en una sola
     lista y el alumno no distinguía a qué profesor le correspondía cada duda;
     ahora van aparte, con la fecha de término a la vista y la nota de para qué
     sirve esa ventana. El chat funciona igual en ambas. */
  bool _esAnterior(Map<String, dynamic> h) =>
      h['esAnterior'] == true || '${h['esAnterior']}' == 'true';

  /* (21-sep) LA FECHA DE TÉRMINO, EN ESPAÑOL.
     La tarjeta ponía «Concluida el» con la fecha tal como la guarda la hoja,
     y a veces llegaba en inglés («Sat Sep 12 2026 00:00:00 GMT-0700»). El
     Guardián ya manda terminoCorto (dd/MM/aaaa); si faltara, se arma aquí
     desde la fecha original, y si no se puede leer, no se muestra. */
  String _fechaTermino(Map<String, dynamic> h) {
    final corto = '${h['terminoCorto'] ?? ''}'.trim();
    if (corto.isNotEmpty) return corto;
    final d = DateTime.tryParse('${h['termino'] ?? ''}'.trim());
    if (d == null) return '';
    final l = d.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/'
        '${l.month.toString().padLeft(2, '0')}/${l.year}';
  }

  List<Widget> _seccionadas(List<Map<String, dynamic>> vis) {
    final enCurso = vis.where((h) => !_esAnterior(h)).toList();
    final cerradas = vis.where(_esAnterior).toList();
    final out = <Widget>[];

    if (enCurso.isNotEmpty) {
      if (cerradas.isNotEmpty) out.add(_encabezadoSeccion('En curso', null));
      out.addAll(enCurso.map(_tarjeta));
    }
    if (cerradas.isNotEmpty) {
      out.add(_encabezadoSeccion(
          'Materias recién concluidas',
          _rol == 'docente'
              ? 'Tus alumnos pueden escribirte hasta 30 días después del cierre.'
              : 'Puedes escribirle a tu profesor hasta 30 días después del '
                  'cierre, por ejemplo para aclarar tu calificación.'));
      out.addAll(cerradas.map(_tarjeta));
    }
    return out;
  }

  Widget _encabezadoSeccion(String titulo, String? nota) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo,
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w800, letterSpacing: .3)),
          if (nota != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(nota,
                  style: TextStyle(fontSize: 11, color: cessumMuted(context))),
            ),
        ],
      ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> h) {
    final sinLeer =
        (h['sinLeer'] is num) ? (h['sinLeer'] as num).toInt() : 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        onTap: () => _abrir(h),
        leading: CircleAvatar(
          backgroundColor:
              sinLeer > 0 ? cessumRed : cessumGold.withValues(alpha: 0.25),
          child: Icon(
              h['conRol'] == 'docente' ? Icons.school : Icons.person,
              size: 19,
              color: sinLeer > 0 ? Colors.white : cessumGold),
        ),
        title: Text('${h['conNombre']}',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${h['materia']}${h['grupo'] != null && '${h['grupo']}'.isNotEmpty ? ' · ${h['grupo']}' : ''}',
                style: TextStyle(fontSize: 11.5, color: cessumGold)),
            if (_esAnterior(h))
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      color: cessumGold.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(
                      'Concluida${_fechaTermino(h).isNotEmpty ? ' el ${_fechaTermino(h)}' : ''} · abierta 30 días',
                      style: const TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              ),
            if (h['ultimo'] != null && '${h['ultimo']}'.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('${h['ultimo']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11.5, color: cessumMuted(context))),
              ),
            // (ago-18) Estado y reloj, como en la Mesa de Ayuda: una
            // conversación sin responder tiene que verse, no perderse entre
            // las demás.
            if (h['estado'] != null && '${h['estado']}'.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: _colorUrgencia(h).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text('${h['estado']}',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: _colorUrgencia(h))),
                  ),
                  if ((h['horasSinResponder'] is num) &&
                      (h['horasSinResponder'] as num) > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(
                          'hace ${(h['horasSinResponder'] as num).toInt()} h',
                          style: TextStyle(
                              fontSize: 10, color: cessumMuted(context))),
                    ),
                ]),
              ),
          ],
        ),
        trailing: sinLeer > 0
            ? Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: cessumRed,
                    borderRadius: BorderRadius.circular(11)),
                child: Text('$sinLeer',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800)),
              )
            : Icon(Icons.chevron_right, color: cessumFaint(context)),
      ),
    );
  }

  Color _colorUrgencia(Map<String, dynamic> h) {
    switch ('${h['urgencia'] ?? ''}') {
      case 'vencido':
        return const Color(0xFFC62828);
      case 'pronto':
        return const Color(0xFFB08D57);
      case 'abierto':
        return const Color(0xFF1E8E3E);
      default:
        return cessumMuted(context);
    }
  }

  Future<void> _abrir(Map<String, dynamic> h) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _HiloScreen(correo: _correo, hilo: h),
      ),
    );
    _cargar();
  }
}

// ═══════════════════════════ La conversación ═══════════════════════════
class _HiloScreen extends StatefulWidget {
  final String correo;
  final Map<String, dynamic> hilo;
  const _HiloScreen({required this.correo, required this.hilo});

  @override
  State<_HiloScreen> createState() => _HiloScreenState();
}

class _HiloScreenState extends State<_HiloScreen> {
  final _ctrl = TextEditingController();
  // (24-sep) Mejorar redacción con IA: se ve el resultado y se puede deshacer.
  bool _mejorando = false;

  Future<void> _mejorar() async {
    final original = _ctrl.text.trim();
    if (original.length < 5 || _mejorando) return;
    setState(() => _mejorando = true);
    try {
      final r = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'},
              body: jsonEncode({
                'accion': 'texto_ia_mejorar',
                'texto': original,
                'proposito': 'mensaje entre un alumno y su docente sobre una materia',
              }))
          .timeout(const Duration(seconds: 60));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      final nuevo = '${d['texto'] ?? ''}'.trim();
      if (!mounted) return;
      if (d['ok'] == true && nuevo.isNotEmpty) {
        _ctrl.text = nuevo;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Redacción mejorada. Revísala antes de enviar.'),
          action: SnackBarAction(label: 'Deshacer', onPressed: () => _ctrl.text = original),
          duration: const Duration(seconds: 8),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${d['error'] ?? 'No se pudo mejorar la redacción.'}')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo conectar para mejorar la redacción.')));
      }
    }
    if (mounted) setState(() => _mejorando = false);
  }
  final _scroll = ScrollController();
  List<Map<String, dynamic>> _msjs = [];
  bool _cargando = true;
  bool _enviando = false;
  /// Guía institucional de respuesta. Solo llega cuando toca responderle a un
  /// alumno; el backend decide cuándo y con qué tema.
  Map<String, dynamic>? _sugerencias;
  bool _verSugerencias = true;
  // (ago-24) TIPIFICACIÓN DEL PRIMER MENSAJE.
  // Solo se pide al abrir la conversación: es la clasificación del hilo, no
  // de cada línea. Sin ella no se puede saber en qué se le va el tiempo al
  // docente ni qué dudas se repiten curso tras curso — "los alumnos
  // preguntan mucho" pasa a ser "el 60% son dudas de la actividad 3".
  String _tipo = 'actividad';
  static const List<List<String>> _tipos = [
    ['actividad', 'Duda sobre una actividad o tarea'],
    ['contenido', 'Duda sobre el contenido de la clase'],
    ['calificacion', 'Calificación o retroalimentación'],
    ['entrega', 'Problema para entregar en el aula'],
    ['inasistencia', 'Inasistencia o justificación'],
    ['general', 'Duda general del curso'],
    ['otro', 'Otro asunto'],
  ];
  bool get _esPrimero => _msjs.isEmpty;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'mensajes_listar',
        'correo': widget.correo,
        'hilo': '${widget.hilo['hilo']}',
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final d = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _msjs = ((d['mensajes'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _sugerencias = (d['sugerencias'] is Map)
            ? Map<String, dynamic>.from(d['sugerencias'] as Map)
            : null;
        _cargando = false;
      });
      _alFinal();
      // Se marcan como leídos al abrir: eso es también lo que evita que el
      // disparador mande un correo por algo que ya se leyó.
      await http.get(Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'mensajes_leidos',
        'correo': widget.correo,
        'hilo': '${widget.hilo['hilo']}',
      })).timeout(const Duration(seconds: 30));
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  void _alFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _enviar() async {
    final texto = _ctrl.text.trim();
    if (texto.isEmpty) return;
    setState(() => _enviando = true);
    try {
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'mensajes_enviar',
        'de': widget.correo,
        'para': '${widget.hilo['conCorreo']}',
        'materia': '${widget.hilo['materia']}',
        'texto': texto,
        if (_esPrimero) 'tipo': _tipo,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 60));
      final d = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (d['ok'] == true) {
        _ctrl.clear();
        await _cargar();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: cessumRed,
            content: Text('${d['error'] ?? 'No se pudo enviar.'}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: cessumRed, content: Text('$e')));
      }
    }
    if (mounted) setState(() => _enviando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.hilo['conNombre']}',
                style: const TextStyle(fontSize: 16)),
            Text('${widget.hilo['materia']}',
                style: const TextStyle(fontSize: 11, color: Color(0xFFF2ECE1))),
          ],
        ),
      ),
      body: Column(children: [
        Expanded(
          child: _cargando
              ? const Center(child: CircularProgressIndicator(color: cessumRed))
              : _msjs.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(
                            'Aún no hay mensajes. Escribe el primero: queda '
                            'registrado junto a la materia y le llega un aviso '
                            'a la otra persona.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cessumMuted(context))),
                      ),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(14),
                      itemCount: _msjs.length,
                      itemBuilder: (ctx, i) => _burbuja(_msjs[i]),
                    ),
        ),
        // ── Guía de respuesta ──
        // No responde por el docente: le propone un punto de partida alineado
        // con lo que la institución ya decidió, para que la misma pregunta no
        // reciba tres respuestas distintas según a quién le tocó. Se inserta
        // en el cuadro de texto y se edita antes de enviar; nada se manda solo.
        if (_sugerencias != null && _verSugerencias)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            color: cessumGold.withValues(alpha: 0.08),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.lightbulb_outline,
                      size: 16, color: cessumGold),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                        '${_sugerencias!['titulo'] ?? 'Guía de respuesta'}'
                        ' · toca una para usarla y editarla',
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF8A6D3B))),
                  ),
                  InkWell(
                    onTap: () => setState(() => _verSugerencias = false),
                    child: Icon(Icons.close,
                        size: 16, color: cessumMuted(context)),
                  ),
                ]),
                const SizedBox(height: 8),
                for (final t in (_sugerencias!['plantillas'] as List? ?? []))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: InkWell(
                      onTap: () {
                        _ctrl.text = '$t';
                        _ctrl.selection = TextSelection.fromPosition(
                            TextPosition(offset: _ctrl.text.length));
                        setState(() {});
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: cessumGold.withValues(alpha: 0.35)),
                        ),
                        child: Text('$t',
                            style: const TextStyle(
                                fontSize: 12, height: 1.4)),
                      ),
                    ),
                  ),
                Text(
                    'Son un punto de partida institucional, no una respuesta '
                    'automática: revísala y ajústala a tu alumno antes de enviar.',
                    style: TextStyle(
                        fontSize: 10.5, color: cessumMuted(context))),
              ],
            ),
          ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(
                  top: BorderSide(
                      color: cessumMuted(context).withValues(alpha: 0.25))),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Al abrir la conversación: de qué se trata, y el compromiso de
              // respuesta a la vista. Un canal sin plazo se siente igual que
              // escribir al vacío.
              if (_esPrimero) ...[
                DropdownButtonFormField<String>(
                  initialValue: _tipo,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '¿De qué se trata tu consulta?',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final t in _tipos)
                      DropdownMenuItem(value: t[0], child: Text(t[1])),
                  ],
                  onChanged: (v) => setState(() => _tipo = v ?? _tipo),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: cessumGold.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                      'Al enviar, tu profesor recibe un correo y cuenta con '
                      '24 horas para la primera respuesta.\n'
                      'Éste es el único canal para dudas: no se atienden por '
                      'WhatsApp, redes ni teléfono personal. Aquí queda '
                      'registro de lo que preguntas y de lo que se te responde.',
                      style: TextStyle(fontSize: 11.5, height: 1.35)),
                ),
                const SizedBox(height: 8),
              ],
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 2000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Escribe tu mensaje…',
                    border: OutlineInputBorder(),
                    isDense: true,
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Mejorar redacción con IA',
                onPressed: (_enviando || _mejorando) ? null : _mejorar,
                icon: _mejorando
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome, color: cessumGold),
              ),
              IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: cessumRed),
                onPressed: _enviando ? null : _enviar,
                icon: _enviando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send, color: Colors.white, size: 20),
              ),
            ]),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _burbuja(Map<String, dynamic> m) {
    final mio = m['mio'] == true;
    return Align(
      alignment: mio ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: mio ? cessumRed.withValues(alpha: 0.10) : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: mio
                  ? cessumRed.withValues(alpha: 0.30)
                  : cessumMuted(context).withValues(alpha: 0.22)),
        ),
        child: Column(
          crossAxisAlignment:
              mio ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!mio)
              Text('${m['nombre']}',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: cessumGold)),
            Text('${m['texto']}',
                style: const TextStyle(fontSize: 13.5, height: 1.45)),
            const SizedBox(height: 3),
            Text('${m['fecha']}',
                style:
                    TextStyle(fontSize: 10, color: cessumMuted(context))),
          ],
        ),
      ),
    );
  }
}
