// convocatoria_docente_screen.dart · Aula CESSUM (admin)
// ---------------------------------------------------------------------------
// (31-ago-2026) SALA DE CONTROL DE LA CLASE MUESTRA, desde la app.
//
// Vicerrectoría va a estar en movimiento los días de sesiones (1, 2 y 3 de
// septiembre) y el panel de cessum.mx está pensado para escritorio. Esta
// pantalla es la versión de bolsillo: el día hora por hora, semáforo por
// sesión (consentimiento, presentación, cuenta Google, docente, Meet,
// observadores), abrir/copiar el Meet, marcar asistencia, mandar el
// recordatorio, y arriba los contadores de la Decisión final y del Diplomado.
//
// AUTOCONTENIDA: solo flutter, http y dart:convert. Habla con guardian.php
// directo (GET docsol_sala / docsol_fase2_resultados / diplomado_estado,
// POST docsol_fase2_asistencia / docsol_fase2_recordar). Se identifica con el
// correo del administrador (`actor`): el Guardián lo traduce a la clave del
// comité (CMTE_POR_ACTOR). Si se abre con un correo que no es de mando, pide
// la clave personal y la guarda en memoria mientras dure la sesión.
//
// CÓMO ENGANCHARLA (una tarjeta en el menú de administración):
//   Navigator.push(context, MaterialPageRoute(
//     builder: (_) => ConvocatoriaDocenteScreen(actor: correoDelAdmin)));
// ---------------------------------------------------------------------------
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

const String _kGuardian = 'https://app.cessum.mx/guardian.php';

class ConvocatoriaDocenteScreen extends StatefulWidget {
  /// Correo institucional del administrador (vicerrectoria@ / rectoria@).
  final String actor;
  const ConvocatoriaDocenteScreen({super.key, this.actor = ''});

  @override
  State<ConvocatoriaDocenteScreen> createState() => _ConvocatoriaDocenteScreenState();
}

class _ConvocatoriaDocenteScreenState extends State<ConvocatoriaDocenteScreen> {
  // Paleta institucional
  static const Color rojo = Color(0xFFB11D29);
  static const Color rojoOsc = Color(0xFF8E1621);
  static const Color oro = Color(0xFFA56B16);
  static const Color verde = Color(0xFF1E7A38);
  static const Color crema = Color(0xFFF7F3EA);
  static const Color linea = Color(0xFFE8DFCE);
  static const Color gris = Color(0xFF6E6E6E);

  /// Clave personal del comité, si el correo no es de mando. Vive en memoria.
  static String _claveMemoria = '';

  Map<String, dynamic>? _sala;
  Map<String, dynamic>? _res;
  Map<String, dynamic>? _dip;
  String _dia = '';
  bool _cargando = false;
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

  Future<Map<String, dynamic>?> _get(String accion, [Map<String, String>? extra]) async {
    final q = <String, String>{'accion': accion, ..._cred(), ...?extra, '_ts': DateTime.now().millisecondsSinceEpoch.toString()};
    try {
      final r = await http.get(Uri.parse(_kGuardian).replace(queryParameters: q)).timeout(const Duration(seconds: 60));
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
          .post(Uri.parse('$_kGuardian?accion=$accion'), headers: {'Content-Type': 'text/plain;charset=utf-8'}, body: jsonEncode(body))
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
    final extra = _dia.isNotEmpty ? {'dia': _dia} : null;
    final sala = await _get('docsol_sala', extra);
    if (sala == null || sala['ok'] != true) {
      final err = (sala?['error'] ?? 'sin respuesta').toString();
      setState(() {
        _cargando = false;
        _pideClave = err.toLowerCase().contains('clave');
        _error = _pideClave ? 'Este correo no es de mando. Escribe tu clave personal del comité.' : err;
      });
      return;
    }
    // Resultados y diplomado en paralelo; si fallan, la sala se muestra igual.
    final otros = await Future.wait([_get('docsol_fase2_resultados'), _get('diplomado_estado')]);
    setState(() {
      _sala = sala;
      _dia = (sala['dia'] ?? '').toString();
      _res = (otros[0]?['ok'] == true) ? otros[0] : null;
      _dip = (otros[1]?['ok'] == true) ? otros[1] : null;
      _cargando = false;
      _pideClave = false;
    });
  }

  void _aviso(String txt, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(txt),
      backgroundColor: err ? rojoOsc : verde,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ------------------------------------------------------------ acciones
  Future<void> _marcarAsistencia(Map<String, dynamic> x, String estado) async {
    final r = await _post('docsol_fase2_asistencia', {'folio': x['folio'], 'estado': estado});
    if (r?['ok'] == true) {
      _aviso((r?['nota'] ?? 'Guardado').toString());
      _cargar();
    } else {
      _aviso((r?['error'] ?? 'No se pudo guardar').toString(), err: true);
    }
  }

  Future<void> _recordatorio(Map<String, dynamic> x) async {
    final correo = (x['correo'] ?? '').toString();
    final google = (x['correoGoogle'] ?? '').toString();
    final para = google.isNotEmpty && google != correo ? '$correo y $google' : correo;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enviar recordatorio'),
        content: Text('A ${x['nombre']} ($para): día, hora de Sonora, asignatura, docente, Meet y lista técnica. ¿Enviar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: rojo), onPressed: () => Navigator.pop(ctx, true), child: const Text('Enviar')),
        ],
      ),
    );
    if (ok != true) return;
    final r = await _post('docsol_fase2_recordar', {'folio': x['folio']});
    if (r?['ok'] == true) {
      _aviso((r?['nota'] ?? 'Enviado').toString());
      _cargar();
    } else {
      _aviso((r?['error'] ?? 'No se pudo enviar').toString(), err: true);
    }
  }

  Future<void> _copiar(String txt, String que) async {
    await Clipboard.setData(ClipboardData(text: txt));
    _aviso('$que copiado al portapapeles');
  }

  // ------------------------------------------------------------------ UI
  @override
  Widget build(BuildContext context) {
    final sala = _sala;
    return Scaffold(
      backgroundColor: crema,
      appBar: AppBar(
        backgroundColor: rojo,
        foregroundColor: Colors.white,
        title: const Text('Clase muestra · Sala de control'),
        actions: [
          IconButton(tooltip: 'Actualizar', onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando && sala == null
          ? const Center(child: CircularProgressIndicator(color: rojo))
          : _pideClave
              ? _vistaClave()
              : _error.isNotEmpty && sala == null
                  ? _vistaError()
                  : RefreshIndicator(
                      color: rojo,
                      onRefresh: _cargar,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
                        children: [
                          if (_error.isNotEmpty) _cajaError(_error),
                          _contadores(),
                          const SizedBox(height: 10),
                          _selectorDia(),
                          const SizedBox(height: 8),
                          _resumenDia(),
                          const SizedBox(height: 8),
                          ..._filasHoras(),
                          const SizedBox(height: 14),
                          _sinRegistrar(),
                        ],
                      ),
                    ),
    );
  }

  Widget _vistaClave() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock_outline, size: 48, color: oro),
          const SizedBox(height: 12),
          Text(_error, textAlign: TextAlign.center, style: const TextStyle(color: gris)),
          const SizedBox(height: 16),
          TextField(
            controller: _claveCtrl,
            decoration: const InputDecoration(labelText: 'Clave del comité', border: OutlineInputBorder()),
            obscureText: true,
            onSubmitted: (_) { _claveMemoria = _claveCtrl.text.trim(); _cargar(); },
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: rojo),
            onPressed: () { _claveMemoria = _claveCtrl.text.trim(); _cargar(); },
            child: const Text('Entrar'),
          ),
        ],
      ),
    );
  }

  Widget _vistaError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off, size: 44, color: gris),
          const SizedBox(height: 10),
          Text(_error, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _cargar, child: const Text('Reintentar')),
        ]),
      ),
    );
  }

  Widget _cajaError(String t) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: rojo.withOpacity(.08), border: Border.all(color: rojo.withOpacity(.4)), borderRadius: BorderRadius.circular(10)),
        child: Text(t, style: const TextStyle(fontSize: 13)),
      );

  Widget _kpi(String n, String t, {Color? c}) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: linea), borderRadius: BorderRadius.circular(10)),
          child: Column(children: [
            Text(n, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c ?? const Color(0xFF2A2A2A))),
            Text(t, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: gris, letterSpacing: .3)),
          ]),
        ),
      );

  Widget _contadores() {
    final s = _sala!;
    final r = _res?['resumen'] as Map<String, dynamic>?;
    final d = _dip;
    return Column(children: [
      Row(children: [
        _kpi('${s['sesiones']}', 'sesiones\nhoy'),
        const SizedBox(width: 6),
        _kpi('${s['listos']}', 'listas', c: verde),
        const SizedBox(width: 6),
        _kpi('${s['conFaltas']}', 'con\nfaltantes', c: oro),
        const SizedBox(width: 6),
        _kpi('${(s['sinRegistrar'] as List?)?.length ?? 0}', 'sin\nregistrar', c: rojo),
      ]),
      if (r != null || d != null) const SizedBox(height: 6),
      if (r != null || d != null)
        Row(children: [
          if (r != null) _kpi('${r['aceptados']}', 'aceptados\nfase 2', c: verde),
          if (r != null) const SizedBox(width: 6),
          if (r != null) _kpi('${r['sinDictamen']}', 'sin\ndictamen', c: oro),
          if (d != null) const SizedBox(width: 6),
          if (d != null) _kpi('${d['inscritos']}', 'diplomado\ninscritos'),
          if (d != null) const SizedBox(width: 6),
          if (d != null) _kpi('${d['acreditan']}', 'acreditan', c: verde),
        ]),
    ]);
  }

  Widget _selectorDia() {
    final dias = (_sala!['dias'] as List?) ?? [];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: dias.map((dd) {
          final iso = (dd['iso'] ?? '').toString();
          final act = iso == _dia;
          final n = act ? _sala!['sesiones'] : ((_sala!['otrosDias'] as Map?)?[iso] ?? 0);
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text('${(dd['nombre'] ?? '').toString()} ($n)'),
              selected: act,
              selectedColor: rojoOsc,
              labelStyle: TextStyle(color: act ? Colors.white : const Color(0xFF4A4A4A), fontWeight: FontWeight.w600, fontSize: 12),
              onSelected: (_) { setState(() => _dia = iso); _cargar(); },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _resumenDia() {
    final s = _sala!;
    return Text(
      '${s['diaNombre']} · hora de Sonora · plazo: ${(s['plazo']?['limiteTxt'] ?? 'sin fijar')}${s['plazo']?['vencido'] == true ? ' (VENCIDO)' : ''}',
      style: const TextStyle(fontSize: 12, color: gris),
    );
  }

  List<Widget> _filasHoras() {
    final s = _sala!;
    final horas = (s['horas'] as List?) ?? [];
    final esHoy = s['dia'] == s['hoy'];
    final ahora = (s['ahoraHora'] is num) ? (s['ahoraHora'] as num).toInt() : -1;
    return horas.map<Widget>((h) {
      final hora = (h['hora'] as num).toInt();
      final x = h['sesion'] as Map<String, dynamic>?;
      final esAhora = esHoy && hora == ahora;
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: x == null ? Colors.white : (x['listo'] == true ? verde.withOpacity(.07) : oro.withOpacity(.08)),
          border: Border.all(color: esAhora ? rojo : linea, width: esAhora ? 2 : 1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 58,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: esAhora ? rojo : const Color(0xFFF5F1E8),
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(11)),
              ),
              child: Text(h['horaTxt'].toString(), textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w800, color: esAhora ? Colors.white : rojoOsc)),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: x == null
                    ? const Text('— libre —', style: TextStyle(color: Color(0xFFB9B2A3), fontStyle: FontStyle.italic))
                    : _tarjetaSesion(x),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _flag(String t, bool ok) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: ok ? verde.withOpacity(.14) : rojo.withOpacity(.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(t, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: ok ? verde : rojo)),
      );

  Widget _tarjetaSesion(Map<String, dynamic> x) {
    final meet = (x['meet'] ?? '').toString();
    final asis = (x['asistencia'] ?? '').toString();
    final obs = (x['observadores'] as List?)?.join(', ') ?? '';
    final faltan = (x['faltan'] as List?)?.join(', ') ?? '';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(x['nombre'].toString(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
      Text('${x['folio']} · ${x['grado']} · ${x['ciudad']}${(x['telefono'] ?? '').toString().isNotEmpty ? ' · ${x['telefono']}' : ''}',
          style: const TextStyle(fontSize: 11.5, color: gris)),
      const SizedBox(height: 3),
      Text('Asignatura: ${x['asignatura']}', style: const TextStyle(fontSize: 12)),
      Text('Docente: ${(x['docente'] ?? '').toString().isEmpty ? 'sin asignar' : x['docente']} · Observadores: ${obs.isEmpty ? 'ninguno' : obs}',
          style: TextStyle(fontSize: 11.5, color: (x['docente'] ?? '').toString().isEmpty || obs.isEmpty ? rojo : gris)),
      if (asis.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(asis, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: asis.toLowerCase().startsWith('asisti') ? verde : rojo)),
        ),
      const SizedBox(height: 6),
      Wrap(spacing: 4, runSpacing: 4, children: [
        _flag('consentimiento', x['consentimiento'] == true),
        _flag('presentación', x['tienePresentacion'] == true),
        _flag('cuenta Google', (x['correoGoogle'] ?? '').toString().isNotEmpty),
        _flag('docente', (x['docente'] ?? '').toString().isNotEmpty),
        _flag('Meet', meet.isNotEmpty),
        _flag('observadores', obs.isNotEmpty),
        if ((x['grabacion'] ?? '').toString().isNotEmpty) _flag('grabación', true),
        if ((x['transcripcion'] ?? '').toString().isNotEmpty) _flag('transcripción', true),
      ]),
      if (faltan.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Falta: $faltan', style: const TextStyle(fontSize: 11, color: oro))),
      const SizedBox(height: 8),
      Wrap(spacing: 6, runSpacing: 6, children: [
        if (meet.isNotEmpty)
          _btn('Copiar Meet', Icons.copy, () => _copiar(meet, 'Meet')),
        if ((x['correo'] ?? '').toString().isNotEmpty)
          _btn('Copiar correo', Icons.alternate_email, () => _copiar(x['correo'].toString(), 'Correo')),
        _btn('Recordatorio', Icons.notifications_active_outlined, () => _recordatorio(x)),
        _menuAsistencia(x),
      ]),
    ]);
  }

  Widget _btn(String t, IconData i, VoidCallback f) => OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: rojoOsc,
          side: const BorderSide(color: linea),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          minimumSize: const Size(0, 34),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        onPressed: f,
        icon: Icon(i, size: 16),
        label: Text(t),
      );

  Widget _menuAsistencia(Map<String, dynamic> x) {
    return PopupMenuButton<String>(
      tooltip: 'Asistencia',
      onSelected: (v) => _marcarAsistencia(x, v),
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'Asistió', child: Text('✔ Asistió')),
        PopupMenuItem(value: 'No se presentó', child: Text('✖ No se presentó')),
        PopupMenuItem(value: 'Reprogramada', child: Text('↻ Reprogramada')),
        PopupMenuItem(value: 'Cancelada', child: Text('— Cancelada')),
        PopupMenuItem(value: '', child: Text('Quitar marca')),
      ],
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(border: Border.all(color: linea), borderRadius: BorderRadius.circular(20)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.how_to_reg_outlined, size: 16, color: rojoOsc),
          SizedBox(width: 6),
          Text('Asistencia', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: rojoOsc)),
          Icon(Icons.arrow_drop_down, size: 18, color: rojoOsc),
        ]),
      ),
    );
  }

  Widget _sinRegistrar() {
    final l = (_sala!['sinRegistrar'] as List?) ?? [];
    if (l.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: linea), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${l.length} invitado(s) sin registrar día y hora', style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        ...l.map((z) => Text('· ${z['nombre']} (${z['correo']})', style: const TextStyle(fontSize: 12, color: gris))),
      ]),
    );
  }
}
