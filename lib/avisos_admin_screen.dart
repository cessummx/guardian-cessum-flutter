// avisos_admin_screen.dart · Aula CESSUM (admin)
// ---------------------------------------------------------------------------
// (31-ago-2026) CENTRO DE AVISOS DEL ADMINISTRADOR.
//
// Todo lo que hoy llega repartido por correo, en una sola lista: actas sin
// validar, justificaciones, bajas, cambios de horario, reposiciones,
// recursamientos, cambios de calificación, incidencias, mensajes de alumnos
// sin leer, contratos por validar, registros de la clase muestra y
// planeaciones del diplomado. Lo pendiente primero; lo nuevo desde la última
// vez marcado con un punto. Filtros por grupo, buscador, "marcar todo como
// leído" (lo pendiente sigue listado: leer no resuelve).
//
// AUTOCONTENIDA: flutter + http + dart:convert. guardian.php:
//   GET  avisos_admin&actor=correo[&dias=14]
//   POST avisos_admin_leido {actor}
//
// ENGANCHE:
//   Navigator.push(context, MaterialPageRoute(
//     builder: (_) => AvisosAdminScreen(actor: correoDelAdmin)));
// Para una campanita con contador en el menú, AvisosAdminScreen.contar(correo)
// devuelve {pendientes, nuevos} sin abrir la pantalla.
// ---------------------------------------------------------------------------
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth/session_store.dart';

const String _kGuardianAv = 'https://app.cessum.mx/guardian.php';

class AvisosAdminScreen extends StatefulWidget {
  /// Correo del administrador. Si viene vacío (p. ej. `const AvisosAdminScreen()`
  /// desde el menú actual), la pantalla lo pide una vez y lo recuerda mientras
  /// dure la sesión de la app.
  final String actor;
  const AvisosAdminScreen({super.key, this.actor = ''});

  /// Correo recordado cuando no se pasó por parámetro.
  static String actorMemoria = '';

  /// Conteo rápido para una insignia en el menú. Devuelve {pendientes, nuevos}.
  static Future<Map<String, int>> contar(String actor) async {
    try {
      final r = await http
          .get(Uri.parse(_kGuardianAv).replace(queryParameters: {'accion': 'avisos_admin', 'actor': actor, 'dias': '7', '_ts': DateTime.now().millisecondsSinceEpoch.toString()}))
          .timeout(const Duration(seconds: 45));
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is Map && j['ok'] == true) return {'pendientes': (j['pendientes'] ?? 0) as int, 'nuevos': (j['nuevos'] ?? 0) as int};
    } catch (_) {}
    return {'pendientes': 0, 'nuevos': 0};
  }

  @override
  State<AvisosAdminScreen> createState() => _AvisosAdminScreenState();
}

class _AvisosAdminScreenState extends State<AvisosAdminScreen> {
  static const Color rojo = Color(0xFFB11D29);
  static const Color rojoOsc = Color(0xFF8E1621);
  static const Color oro = Color(0xFFA56B16);
  static const Color verde = Color(0xFF1E7A38);
  static const Color crema = Color(0xFFF7F3EA);
  static const Color linea = Color(0xFFE8DFCE);
  static const Color gris = Color(0xFF6E6E6E);

  Map<String, dynamic>? _data;
  bool _cargando = true; // (24-sep) arranca cargando mientras toma el correo de la sesión
  String _error = '';
  bool _pideCorreo = false;
  final _correoCtrl = TextEditingController();
  String get _actor => widget.actor.trim().isNotEmpty ? widget.actor.trim() : AvisosAdminScreen.actorMemoria;
  String _grupo = 'Todos';
  bool _soloPend = false;
  String _busca = '';
  int _dias = 14;

  static const Map<String, IconData> _iconos = {
    'acta': Icons.fact_check_outlined,
    'justificacion': Icons.event_busy_outlined,
    'baja': Icons.person_remove_outlined,
    'cambio_horario': Icons.schedule_outlined,
    'reposicion': Icons.replay_outlined,
    'recursamiento': Icons.school_outlined,
    'calif_cambio': Icons.grading_outlined,
    'incidencia': Icons.report_problem_outlined,
    'mensaje': Icons.chat_bubble_outline,
    'contrato': Icons.description_outlined,
    'fase2': Icons.co_present_outlined,
    'diplomado': Icons.workspace_premium_outlined,
  };

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  /// (24-sep) Sin correo por parámetro, se toma el de la sesión (el REAL, no el de
  /// «Ver como profesor»). Solo si no hay sesión se pide escribirlo, como antes.
  Future<void> _iniciar() async {
    if (_actor.isEmpty) {
      final real = ((await SessionStore.realEmail()) ?? '').trim().toLowerCase();
      if (real.isNotEmpty) AvisosAdminScreen.actorMemoria = real;
    }
    if (!mounted) return;
    if (_actor.isEmpty) {
      setState(() => _pideCorreo = true);
    } else {
      _cargar();
    }
  }

  @override
  void dispose() {
    _correoCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    if (_actor.isEmpty) { setState(() => _pideCorreo = true); return; }
    setState(() { _cargando = true; _error = ''; _pideCorreo = false; });
    try {
      final r = await http
          .get(Uri.parse(_kGuardianAv).replace(queryParameters: {'accion': 'avisos_admin', 'actor': _actor, 'dias': '$_dias', '_ts': DateTime.now().millisecondsSinceEpoch.toString()}))
          .timeout(const Duration(seconds: 90));
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is! Map<String, dynamic> || j['ok'] != true) throw Exception((j is Map ? j['error'] : null) ?? 'Respuesta inesperada');
      setState(() { _data = j; _cargando = false; });
    } catch (e) {
      final msg = '$e'.replaceFirst('Exception: ', '');
      setState(() { _cargando = false; _error = msg; _pideCorreo = msg.toLowerCase().contains('administrador'); });
    }
  }

  Widget _vistaCorreo() => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.alternate_email, size: 48, color: oro),
          const SizedBox(height: 12),
          Text(_error.isNotEmpty ? _error : 'Escribe tu correo institucional de administrador para cargar tus avisos.', textAlign: TextAlign.center, style: const TextStyle(color: gris)),
          const SizedBox(height: 16),
          TextField(
            controller: _correoCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Correo @cessum.mx', border: OutlineInputBorder()),
            onSubmitted: (_) { AvisosAdminScreen.actorMemoria = _correoCtrl.text.trim().toLowerCase(); _cargar(); },
          ),
          const SizedBox(height: 12),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: rojo), onPressed: () { AvisosAdminScreen.actorMemoria = _correoCtrl.text.trim().toLowerCase(); _cargar(); }, child: const Text('Entrar')),
        ]),
      );

  Future<void> _marcarLeido() async {
    try {
      final r = await http
          .post(Uri.parse('$_kGuardianAv?accion=avisos_admin_leido'), headers: {'Content-Type': 'text/plain;charset=utf-8'}, body: jsonEncode({'accion': 'avisos_admin_leido', 'actor': _actor}))
          .timeout(const Duration(seconds: 45));
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is Map && j['ok'] == true) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text((j['nota'] ?? 'Listo').toString()), backgroundColor: verde, behavior: SnackBarBehavior.floating));
        _cargar();
      }
    } catch (_) {}
  }

  List<Map<String, dynamic>> _lista() {
    final l = ((_data?['avisos'] as List?) ?? []).cast<Map<String, dynamic>>();
    final q = _busca.trim().toLowerCase();
    return l.where((a) {
      if (_grupo != 'Todos' && a['grupo'] != _grupo) return false;
      if (_soloPend && a['pendiente'] != true) return false;
      if (q.isNotEmpty && !('${a['titulo']} ${a['detalle']} ${a['quien']}'.toLowerCase().contains(q))) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final resumen = (d?['resumen'] as Map<String, dynamic>?) ?? {};
    final grupos = ['Todos', ...resumen.keys];
    return Scaffold(
      backgroundColor: crema,
      appBar: AppBar(
        backgroundColor: rojo,
        foregroundColor: Colors.white,
        title: const Text('Avisos'),
        actions: [
          PopupMenuButton<int>(
            tooltip: 'Días hacia atrás',
            initialValue: _dias,
            onSelected: (v) { setState(() => _dias = v); _cargar(); },
            itemBuilder: (_) => const [PopupMenuItem(value: 3, child: Text('3 días')), PopupMenuItem(value: 7, child: Text('7 días')), PopupMenuItem(value: 14, child: Text('14 días')), PopupMenuItem(value: 30, child: Text('30 días'))],
            icon: const Icon(Icons.history),
          ),
          IconButton(tooltip: 'Marcar todo como leído', onPressed: d == null ? null : _marcarLeido, icon: const Icon(Icons.done_all)),
          IconButton(tooltip: 'Actualizar', onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _pideCorreo
          ? _vistaCorreo()
          : _cargando && d == null
          ? const Center(child: CircularProgressIndicator(color: rojo))
          : d == null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.cloud_off, size: 44, color: gris),
                  const SizedBox(height: 10),
                  Text(_error, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: _cargar, child: const Text('Reintentar')),
                ])))
              : RefreshIndicator(
                  color: rojo,
                  onRefresh: _cargar,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
                    children: [
                      _cabecera(d, resumen),
                      const SizedBox(height: 10),
                      _filtros(grupos, resumen),
                      const SizedBox(height: 8),
                      ..._lista().map(_tarjeta),
                      if (_lista().isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Nada con ese filtro.', textAlign: TextAlign.center, style: TextStyle(color: gris))),
                    ],
                  ),
                ),
    );
  }

  Widget _kpi(String n, String t, {Color? c}) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: linea), borderRadius: BorderRadius.circular(10)),
          child: Column(children: [
            Text(n, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c ?? const Color(0xFF2A2A2A))),
            Text(t, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10.5, color: gris)),
          ]),
        ),
      );

  Widget _cabecera(Map<String, dynamic> d, Map<String, dynamic> resumen) {
    return Column(children: [
      Row(children: [
        _kpi('${d['pendientes'] ?? 0}', 'pendientes de acción', c: (d['pendientes'] ?? 0) == 0 ? verde : rojo),
        const SizedBox(width: 6),
        _kpi('${d['nuevos'] ?? 0}', 'nuevos desde la última vez', c: oro),
        const SizedBox(width: 6),
        _kpi('${d['total'] ?? 0}', 'en $_dias días'),
      ]),
      if ((d['leidoHasta'] ?? '').toString().isNotEmpty)
        Padding(padding: const EdgeInsets.only(top: 6), child: Text('Leído hasta ${d['leidoHasta']}', style: const TextStyle(fontSize: 11.5, color: gris))),
    ]);
  }

  Widget _filtros(List<String> grupos, Map<String, dynamic> resumen) {
    return Column(children: [
      TextField(
        decoration: InputDecoration(
          hintText: 'Buscar persona, materia, folio…',
          prefixIcon: const Icon(Icons.search),
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: linea)),
        ),
        onChanged: (v) => setState(() => _busca = v),
      ),
      const SizedBox(height: 6),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          FilterChip(
            label: const Text('Solo pendientes'),
            selected: _soloPend,
            selectedColor: rojo.withOpacity(.15),
            checkmarkColor: rojo,
            onSelected: (v) => setState(() => _soloPend = v),
          ),
          const SizedBox(width: 6),
          ...grupos.map((g) {
            final act = _grupo == g;
            final r = resumen[g] as Map<String, dynamic>?;
            final pend = r?['pendientes'] ?? 0;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(g == 'Todos' ? 'Todos' : '$g${pend > 0 ? ' · $pend' : ''}'),
                selected: act,
                selectedColor: rojoOsc,
                labelStyle: TextStyle(color: act ? Colors.white : const Color(0xFF4A4A4A), fontWeight: FontWeight.w600, fontSize: 12),
                onSelected: (_) => setState(() => _grupo = g),
              ),
            );
          }),
        ]),
      ),
    ]);
  }

  Widget _tarjeta(Map<String, dynamic> a) {
    final pend = a['pendiente'] == true;
    final nuevo = a['nuevo'] == true;
    final icono = _iconos[a['tipo']] ?? Icons.notifications_none;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: pend ? Colors.white : const Color(0xFFFDFBF7),
        border: Border(left: BorderSide(color: pend ? rojo : linea, width: pend ? 4 : 1), top: const BorderSide(color: linea), right: const BorderSide(color: linea), bottom: const BorderSide(color: linea)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: (pend ? rojo : gris).withOpacity(.1), borderRadius: BorderRadius.circular(10)),
          child: Icon(icono, size: 20, color: pend ? rojo : gris),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (nuevo) Container(width: 8, height: 8, margin: const EdgeInsets.only(right: 6), decoration: const BoxDecoration(color: oro, shape: BoxShape.circle)),
            Expanded(child: Text(a['titulo'].toString(), style: TextStyle(fontWeight: pend ? FontWeight.w700 : FontWeight.w600, fontSize: 14))),
          ]),
          if ((a['detalle'] ?? '').toString().isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 2), child: Text(a['detalle'].toString(), style: const TextStyle(fontSize: 12.5, color: Color(0xFF4A4A4A)))),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('${a['fecha']} · ${a['grupo']}${(a['pantalla'] ?? '').toString().isNotEmpty ? ' · ${a['pantalla']}' : ''}', style: const TextStyle(fontSize: 11, color: gris)),
          ),
        ])),
        if (pend) Container(
          margin: const EdgeInsets.only(left: 6),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(color: rojo.withOpacity(.1), borderRadius: BorderRadius.circular(6)),
          child: const Text('PENDIENTE', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: rojo)),
        ),
      ]),
    );
  }
}
