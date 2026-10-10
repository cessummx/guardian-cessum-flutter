// diplomado_admin_screen.dart · Aula CESSUM (admin)
// ---------------------------------------------------------------------------
// (31-ago-2026) DIPLOMADO DOCENTE, desde el celular.
//
// Las sesiones son lunes (y un miércoles) a las 19:00: quien coordina está
// en la sala, no en el escritorio. Esta pantalla sirve para pasar lista en
// vivo, ver quién ya entregó su planeación, copiar el Meet, guardar el
// enlace de la grabación/materiales de la sesión, e inscribir a quien falte.
// Las constancias y el curso de Moodle se emiten desde el panel de
// escritorio (mandan correos; ahí está la vista previa).
//
// AUTOCONTENIDA: flutter + http + dart:convert. guardian.php:
//   GET  diplomado_estado
//   POST diplomado_asistencia {fecha, marcas}, diplomado_sesion, diplomado_inscribir
// Se identifica con el correo del administrador (`actor`) o la clave.
//
// ENGANCHE:
//   Navigator.push(context, MaterialPageRoute(
//     builder: (_) => DiplomadoAdminScreen(actor: correoDelAdmin)));
// ---------------------------------------------------------------------------
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

const String _kGuardianDip = 'https://app.cessum.mx/guardian.php';

class DiplomadoAdminScreen extends StatefulWidget {
  final String actor;
  const DiplomadoAdminScreen({super.key, this.actor = ''});

  @override
  State<DiplomadoAdminScreen> createState() => _DiplomadoAdminScreenState();
}

class _DiplomadoAdminScreenState extends State<DiplomadoAdminScreen> {
  static const Color rojo = Color(0xFFB11D29);
  static const Color rojoOsc = Color(0xFF8E1621);
  static const Color oro = Color(0xFFA56B16);
  static const Color verde = Color(0xFF1E7A38);
  static const Color crema = Color(0xFFF7F3EA);
  static const Color linea = Color(0xFFE8DFCE);
  static const Color gris = Color(0xFF6E6E6E);

  static String _claveMemoria = '';

  Map<String, dynamic>? _dip;
  String _fecha = '';          // sesión seleccionada (yyyy-MM-dd)
  final Map<String, String> _marcas = {}; // folio -> SI | NO | JUST | ''
  bool _cargando = false;
  bool _guardando = false;
  String _error = '';
  bool _pideClave = false;
  final _claveCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _claveCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- red
  Map<String, String> _cred() {
    final m = <String, String>{};
    if (_claveMemoria.isNotEmpty) m['clave'] = _claveMemoria;
    if (widget.actor.trim().isNotEmpty) m['actor'] = widget.actor.trim();
    return m;
  }

  Future<Map<String, dynamic>?> _get(String accion) async {
    final q = <String, String>{'accion': accion, ..._cred(), '_ts': DateTime.now().millisecondsSinceEpoch.toString()};
    try {
      final r = await http.get(Uri.parse(_kGuardianDip).replace(queryParameters: q)).timeout(const Duration(seconds: 60));
      if (r.statusCode != 200) return {'ok': false, 'error': 'HTTP ${r.statusCode}'};
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      return j is Map<String, dynamic> ? j : {'ok': false, 'error': 'Respuesta inesperada'};
    } catch (e) {
      return {'ok': false, 'error': 'Sin conexión: $e'};
    }
  }

  Future<Map<String, dynamic>?> _post(String accion, Map<String, dynamic> datos) async {
    final body = <String, dynamic>{'accion': accion, ..._cred(), ...datos};
    try {
      final r = await http
          .post(Uri.parse('$_kGuardianDip?accion=$accion'), headers: {'Content-Type': 'text/plain;charset=utf-8'}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 90));
      if (r.statusCode != 200) return {'ok': false, 'error': 'HTTP ${r.statusCode}'};
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      return j is Map<String, dynamic> ? j : {'ok': false, 'error': 'Respuesta inesperada'};
    } catch (e) {
      return {'ok': false, 'error': 'Sin conexión: $e'};
    }
  }

  Future<void> _cargar() async {
    setState(() { _cargando = true; _error = ''; });
    final d = await _get('diplomado_estado');
    if (d == null || d['ok'] != true) {
      final err = (d?['error'] ?? 'sin respuesta').toString();
      setState(() {
        _cargando = false;
        _pideClave = err.toLowerCase().contains('clave') || err.toLowerCase().contains('rector');
        _error = _pideClave ? 'Este correo no es de mando. Escribe tu clave personal.' : err;
      });
      return;
    }
    final ses = (d['sesiones'] as List?) ?? [];
    final hoy = (d['hoy'] ?? '').toString();
    if (_fecha.isEmpty || !ses.any((s) => s['fecha'] == _fecha)) {
      _fecha = '';
      for (final s in ses) { if ((s['fecha'] ?? '').toString().compareTo(hoy) >= 0) { _fecha = s['fecha'].toString(); break; } }
      if (_fecha.isEmpty && ses.isNotEmpty) _fecha = ses.last['fecha'].toString();
    }
    _marcas.clear();
    for (final r in (d['roster'] as List? ?? [])) {
      final det = ((r['resumen'] ?? {})['detalle'] as List?) ?? [];
      for (final dd in det) { if (dd['fecha'] == _fecha) _marcas[r['folio'].toString()] = (dd['presente'] ?? '').toString(); }
    }
    setState(() { _dip = d; _cargando = false; _pideClave = false; });
  }

  void _aviso(String txt, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(txt), backgroundColor: err ? rojoOsc : verde, behavior: SnackBarBehavior.floating));
  }

  // ------------------------------------------------------------ acciones
  Future<void> _guardarAsistencia() async {
    if (_fecha.isEmpty) return;
    setState(() => _guardando = true);
    final r = await _post('diplomado_asistencia', {'fecha': _fecha, 'marcas': _marcas});
    setState(() => _guardando = false);
    if (r?['ok'] == true) { _aviso((r?['nota'] ?? 'Asistencia guardada').toString()); _cargar(); }
    else { _aviso((r?['error'] ?? 'No se pudo guardar').toString(), err: true); }
  }

  Future<void> _editarSesion(Map<String, dynamic> s) async {
    final tema = TextEditingController(text: (s['tema'] ?? '').toString());
    final imparte = TextEditingController(text: (s['imparte'] ?? '').toString());
    final mat = TextEditingController(text: (s['materiales'] ?? '').toString());
    final grab = TextEditingController(text: (s['grabacion'] ?? '').toString());
    String estado = (s['estado'] ?? 'Programada').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        title: Text('Sesión ${s['n']} · ${s['fechaTxt']}'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: tema, decoration: const InputDecoration(labelText: 'Tema', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: imparte, decoration: const InputDecoration(labelText: 'Imparte', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: mat, decoration: const InputDecoration(labelText: 'Enlace a materiales', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(controller: grab, decoration: const InputDecoration(labelText: 'Enlace a grabación', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: ['Programada', 'Impartida', 'Cancelada', 'Reprogramada'].contains(estado) ? estado : 'Programada',
            items: const [DropdownMenuItem(value: 'Programada', child: Text('Programada')), DropdownMenuItem(value: 'Impartida', child: Text('Impartida')), DropdownMenuItem(value: 'Cancelada', child: Text('Cancelada')), DropdownMenuItem(value: 'Reprogramada', child: Text('Reprogramada'))],
            onChanged: (v) => setD(() => estado = v ?? estado),
            decoration: const InputDecoration(labelText: 'Estado', border: OutlineInputBorder()),
          ),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: rojo), onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      )),
    );
    if (ok != true) return;
    final r = await _post('diplomado_sesion', {'fecha': s['fecha'], 'tema': tema.text.trim(), 'imparte': imparte.text.trim(), 'materiales': mat.text.trim(), 'grabacion': grab.text.trim(), 'estado': estado});
    if (r?['ok'] == true) { _aviso((r?['nota'] ?? 'Guardado').toString()); _cargar(); } else { _aviso((r?['error'] ?? 'No se pudo guardar').toString(), err: true); }
  }

  Future<void> _inscribirPendientes() async {
    final pend = (_dip?['aceptadosSinInscribir'] as List?) ?? [];
    if (pend.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Inscribir a ${pend.length} aceptado(s)'),
        content: Text(pend.map((z) => '· ${z['nombre']}').join('\n') + '\n\nNo manda correo. La invitación de Calendar sale al crear/actualizar el Meet desde el panel.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: rojo), onPressed: () => Navigator.pop(ctx, true), child: const Text('Inscribir')),
        ],
      ),
    );
    if (ok != true) return;
    final r = await _post('diplomado_inscribir', {});
    if (r?['ok'] == true) { _aviso((r?['nota'] ?? 'Inscritos').toString()); _cargar(); } else { _aviso((r?['error'] ?? 'No se pudo').toString(), err: true); }
  }

  Future<void> _copiar(String t, String que) async {
    await Clipboard.setData(ClipboardData(text: t));
    _aviso('$que copiado');
  }

  // ------------------------------------------------------------------ UI
  @override
  Widget build(BuildContext context) {
    final d = _dip;
    return Scaffold(
      backgroundColor: crema,
      appBar: AppBar(
        backgroundColor: rojo,
        foregroundColor: Colors.white,
        title: const Text('Diplomado docente'),
        actions: [IconButton(tooltip: 'Actualizar', onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh))],
      ),
      body: _cargando && d == null
          ? const Center(child: CircularProgressIndicator(color: rojo))
          : _pideClave
              ? _vistaClave()
              : d == null
                  ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Text(_error, textAlign: TextAlign.center), const SizedBox(height: 12), OutlinedButton(onPressed: _cargar, child: const Text('Reintentar'))])))
                  : RefreshIndicator(
                      color: rojo,
                      onRefresh: _cargar,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                        children: [
                          _cabecera(),
                          const SizedBox(height: 10),
                          _sesiones(),
                          const SizedBox(height: 10),
                          _tarjetaSesionActual(),
                          const SizedBox(height: 10),
                          _roster(),
                        ],
                      ),
                    ),
      bottomNavigationBar: (d != null && _fecha.isNotEmpty)
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: linea))),
                child: Row(children: [
                  OutlinedButton(
                    onPressed: () => setState(() { for (final k in _marcas.keys.toList()) { if (_marcas[k]!.isEmpty) _marcas[k] = 'SI'; } }),
                    child: const Text('Todos ✔ (vacíos)'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: rojo, padding: const EdgeInsets.symmetric(vertical: 12)),
                      onPressed: _guardando ? null : _guardarAsistencia,
                      icon: _guardando ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save_outlined),
                      label: Text('Guardar asistencia S${_sesionActual()?['n'] ?? ''}'),
                    ),
                  ),
                ]),
              ),
            )
          : null,
    );
  }

  Map<String, dynamic>? _sesionActual() {
    for (final s in (_dip?['sesiones'] as List? ?? [])) { if (s['fecha'] == _fecha) return s as Map<String, dynamic>; }
    return null;
  }

  Widget _vistaClave() => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.lock_outline, size: 48, color: oro),
          const SizedBox(height: 12),
          Text(_error, textAlign: TextAlign.center, style: const TextStyle(color: gris)),
          const SizedBox(height: 16),
          TextField(controller: _claveCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Clave', border: OutlineInputBorder()), onSubmitted: (_) { _claveMemoria = _claveCtrl.text.trim(); _cargar(); }),
          const SizedBox(height: 12),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: rojo), onPressed: () { _claveMemoria = _claveCtrl.text.trim(); _cargar(); }, child: const Text('Entrar')),
        ]),
      );

  Widget _kpi(String n, String t, {Color? c}) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: linea), borderRadius: BorderRadius.circular(10)),
          child: Column(children: [
            Text(n, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c ?? const Color(0xFF2A2A2A))),
            Text(t, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: gris)),
          ]),
        ),
      );

  Widget _cabecera() {
    final d = _dip!;
    final pend = (d['aceptadosSinInscribir'] as List?) ?? [];
    final meet = (d['meet'] ?? '').toString();
    return Column(children: [
      Row(children: [
        _kpi('${d['inscritos']}', 'inscritos'),
        const SizedBox(width: 6),
        _kpi('${d['acreditan']}', 'acreditan', c: verde),
        const SizedBox(width: 6),
        _kpi('${d['sinPlaneacion']}', 'sin\nplaneación', c: (d['sinPlaneacion'] ?? 0) == 0 ? verde : oro),
        const SizedBox(width: 6),
        _kpi('${pend.length}', 'por\ninscribir', c: pend.isEmpty ? verde : rojo),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        if (meet.isNotEmpty) _btn('Copiar Meet', Icons.copy, () => _copiar(meet, 'Meet')),
        if (pend.isNotEmpty) _btn('Inscribir ${pend.length} aceptado(s)', Icons.person_add_alt_1_outlined, _inscribirPendientes),
      ]),
    ]);
  }

  Widget _btn(String t, IconData i, VoidCallback f) => OutlinedButton.icon(
        style: OutlinedButton.styleFrom(foregroundColor: rojoOsc, side: const BorderSide(color: linea), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), minimumSize: const Size(0, 34), textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        onPressed: f,
        icon: Icon(i, size: 16),
        label: Text(t),
      );

  Widget _sesiones() {
    final ses = (_dip!['sesiones'] as List?) ?? [];
    final hoy = (_dip!['hoy'] ?? '').toString();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: ses.map((s) {
          final f = s['fecha'].toString();
          final act = f == _fecha;
          final esHoy = f == hoy;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text('S${s['n']} · ${f.substring(8, 10)}/${f.substring(5, 7)}${esHoy ? ' · HOY' : ''}'),
              selected: act,
              selectedColor: rojoOsc,
              side: BorderSide(color: esHoy ? rojo : linea),
              labelStyle: TextStyle(color: act ? Colors.white : const Color(0xFF4A4A4A), fontWeight: FontWeight.w600, fontSize: 12),
              onSelected: (_) { setState(() => _fecha = f); _cargar(); },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _tarjetaSesionActual() {
    final s = _sesionActual();
    if (s == null) return const SizedBox.shrink();
    final meet = (s['meet'] ?? '').toString();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: linea), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('Sesión ${s['n']} · ${s['fechaTxt']} · ${_dip!['horario']} h', style: const TextStyle(fontWeight: FontWeight.w700))),
          IconButton(tooltip: 'Editar sesión', onPressed: () => _editarSesion(s), icon: const Icon(Icons.edit_outlined, size: 20, color: rojoOsc)),
        ]),
        Text((s['tema'] ?? '').toString(), style: const TextStyle(fontSize: 13)),
        if ((s['imparte'] ?? '').toString().isNotEmpty) Text('Imparte: ${s['imparte']}', style: const TextStyle(fontSize: 12.5, color: gris)),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 4, children: [
          _pill((s['estado'] ?? 'Programada').toString(), gris),
          if (meet.isNotEmpty) _pill('Meet listo', verde) else _pill('sin Meet', rojo),
          if ((s['materiales'] ?? '').toString().isNotEmpty) _pill('materiales', verde),
          if ((s['grabacion'] ?? '').toString().isNotEmpty) _pill('grabación', verde),
          if ((s['recordadoEl'] ?? '').toString().isNotEmpty) _pill('recordatorio enviado', verde),
        ]),
      ]),
    );
  }

  Widget _pill(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: c.withOpacity(.14), borderRadius: BorderRadius.circular(6)),
        child: Text(t, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c)),
      );

  Widget _roster() {
    final roster = ((_dip!['roster'] as List?) ?? []).cast<Map<String, dynamic>>();
    if (roster.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('Nadie inscrito todavía.', textAlign: TextAlign.center, style: TextStyle(color: gris)));
    return Column(children: roster.map(_filaParticipante).toList());
  }

  Widget _filaParticipante(Map<String, dynamic> r) {
    final baja = (r['estatus'] ?? '') == 'Baja';
    final res = (r['resumen'] as Map<String, dynamic>?) ?? {};
    final marca = _marcas[r['folio'].toString()] ?? '';
    final pct = (res['pct'] ?? 0);
    final acredita = res['acredita'] == true;
    return Opacity(
      opacity: baja ? .5 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(left: BorderSide(color: acredita ? verde : linea, width: acredita ? 4 : 1), top: const BorderSide(color: linea), right: const BorderSide(color: linea), bottom: const BorderSide(color: linea)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r['nombre'].toString(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            Text('${r['folio']} · ${(r['correoGoogle'] ?? '').toString().isNotEmpty ? r['correoGoogle'] : r['correo']}', style: const TextStyle(fontSize: 11, color: gris)),
            const SizedBox(height: 4),
            Wrap(spacing: 5, runSpacing: 4, children: [
              _pill('$pct % asistencia', pct >= (_dip!['asistenciaMin'] ?? 80) ? verde : oro),
              _pill((r['planeacionURL'] ?? '').toString().isNotEmpty ? 'planeación ✔' : 'sin planeación', (r['planeacionURL'] ?? '').toString().isNotEmpty ? verde : rojo),
              if ((r['estatus'] ?? '') == 'Acreditado') _pill('acreditado', verde) else if (acredita) _pill('cumple', verde),
              if (baja) _pill('baja', rojo),
            ]),
            if ((r['planeacionURL'] ?? '').toString().isNotEmpty)
              TextButton.icon(
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 28), foregroundColor: rojoOsc, textStyle: const TextStyle(fontSize: 11.5)),
                onPressed: () => _copiar(r['planeacionURL'].toString(), 'Enlace de la planeación'),
                icon: const Icon(Icons.link, size: 14),
                label: const Text('Copiar enlace de la planeación'),
              ),
          ])),
          if (!baja && _fecha.isNotEmpty) _selectorMarca(r['folio'].toString(), marca),
        ]),
      ),
    );
  }

  Widget _selectorMarca(String folio, String marca) {
    Widget b(String v, String t, Color c) {
      final sel = marca == v;
      return InkWell(
        onTap: () => setState(() => _marcas[folio] = sel ? '' : v),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: sel ? c : Colors.white, border: Border.all(color: sel ? c : linea), borderRadius: BorderRadius.circular(8)),
          child: Text(t, style: TextStyle(fontWeight: FontWeight.w800, color: sel ? Colors.white : c)),
        ),
      );
    }
    return Column(children: [
      Row(mainAxisSize: MainAxisSize.min, children: [b('SI', '✔', verde), const SizedBox(width: 4), b('NO', '✖', rojo), const SizedBox(width: 4), b('JUST', 'J', oro)]),
    ]);
  }
}
