// resultados_fase2_screen.dart · Aula CESSUM (admin)
// ---------------------------------------------------------------------------
// (31-ago-2026) RESULTADOS DE LA FASE 2 · DICTAMEN DESDE EL CELULAR.
//
// Al terminar cada clase muestra, Vicerrectoría puede dictaminar ahí mismo:
// ve por participante el puntaje del comité (fase 1), el promedio de los
// observadores (con sus recomendaciones), la lectura IA y el puntaje
// integrado orientativo; marca Aceptado / Reserva / No aceptado con motivo;
// y cuando ya nadie queda sin dictamen, valida el acta de resultados con su
// firma. El envío de correos (convocatoria al diplomado y avisos) se deja
// a propósito en el panel de escritorio: es irreversible y conviene verlo
// con la vista previa completa.
//
// AUTOCONTENIDA: flutter + http + dart:convert. Habla con guardian.php:
//   GET  docsol_fase2_resultados, docsol_actares_estado
//   POST docsol_fase2_dictaminar, docsol_actares_firmar
// Se identifica con el correo del administrador (`actor`, mapeado en el
// Guardián a la clave del comité) o con la clave personal.
//
// ENGANCHE:
//   Navigator.push(context, MaterialPageRoute(
//     builder: (_) => ResultadosFase2Screen(actor: correoDelAdmin)));
// ---------------------------------------------------------------------------
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

const String _kGuardianRes = 'https://app.cessum.mx/guardian.php';

class ResultadosFase2Screen extends StatefulWidget {
  final String actor;
  const ResultadosFase2Screen({super.key, this.actor = ''});

  @override
  State<ResultadosFase2Screen> createState() => _ResultadosFase2ScreenState();
}

class _ResultadosFase2ScreenState extends State<ResultadosFase2Screen> {
  static const Color rojo = Color(0xFFB11D29);
  static const Color rojoOsc = Color(0xFF8E1621);
  static const Color oro = Color(0xFFA56B16);
  static const Color verde = Color(0xFF1E7A38);
  static const Color crema = Color(0xFFF7F3EA);
  static const Color linea = Color(0xFFE8DFCE);
  static const Color gris = Color(0xFF6E6E6E);

  static String _claveMemoria = '';

  Map<String, dynamic>? _res;
  Map<String, dynamic>? _acta;
  bool _cargando = false;
  String _error = '';
  bool _pideClave = false;
  String _filtro = 'todos'; // todos | sinDictamen | Aceptado | Reserva | No aceptado
  String _busca = '';
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
      final r = await http.get(Uri.parse(_kGuardianRes).replace(queryParameters: q)).timeout(const Duration(seconds: 60));
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
          .post(Uri.parse('$_kGuardianRes?accion=$accion'), headers: {'Content-Type': 'text/plain;charset=utf-8'}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 120));
      if (r.statusCode != 200) return {'ok': false, 'error': 'HTTP ${r.statusCode}'};
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      return j is Map<String, dynamic> ? j : {'ok': false, 'error': 'Respuesta inesperada'};
    } catch (e) {
      return {'ok': false, 'error': 'Sin conexión: $e'};
    }
  }

  Future<void> _cargar() async {
    setState(() { _cargando = true; _error = ''; });
    final res = await _get('docsol_fase2_resultados');
    if (res == null || res['ok'] != true) {
      final err = (res?['error'] ?? 'sin respuesta').toString();
      setState(() {
        _cargando = false;
        _pideClave = err.toLowerCase().contains('clave') || err.toLowerCase().contains('rector');
        _error = _pideClave ? 'Este correo no es de mando. Escribe tu clave personal del comité.' : err;
      });
      return;
    }
    final acta = await _get('docsol_actares_estado');
    setState(() {
      _res = res;
      _acta = (acta?['ok'] == true) ? acta : null;
      _cargando = false;
      _pideClave = false;
    });
  }

  void _aviso(String txt, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(txt), backgroundColor: err ? rojoOsc : verde, behavior: SnackBarBehavior.floating));
  }

  // ------------------------------------------------------------ acciones
  Future<void> _dictaminar(Map<String, dynamic> x, String decision) async {
    final motivoCtrl = TextEditingController(text: (x['decisionMotivo'] ?? '').toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(decision.isEmpty ? 'Quitar dictamen' : 'Dictaminar: $decision'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(x['nombre'].toString(), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (decision.isNotEmpty)
            TextField(controller: motivoCtrl, decoration: const InputDecoration(labelText: 'Motivo (opcional, interno)', border: OutlineInputBorder()), maxLines: 2),
          const SizedBox(height: 8),
          const Text('No se avisa al aspirante hasta validar el acta de resultados.', style: TextStyle(fontSize: 12, color: gris)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: rojo), onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;
    final r = await _post('docsol_fase2_dictaminar', {'folios': x['folio'], 'decision': decision, 'motivo': motivoCtrl.text.trim()});
    if (r?['ok'] == true) {
      _aviso((r?['nota'] ?? 'Guardado').toString());
      _cargar();
    } else {
      _aviso((r?['error'] ?? 'No se pudo guardar').toString(), err: true);
    }
  }

  Future<void> _firmar() async {
    final a = _acta;
    if (a == null) return;
    final sin = (a['sinDictamen'] as List?)?.length ?? 0;
    if (sin > 0) { _aviso('Faltan $sin dictámenes antes de validar el acta.', err: true); return; }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Validar acta de resultados'),
        content: Text('Aceptados: ${(a['aceptados'] as List?)?.length ?? 0} · Reserva: ${(a['reserva'] as List?)?.length ?? 0} · No aceptados: ${(a['noAceptados'] as List?)?.length ?? 0}.\n\nSu firma queda estampada con fecha y hora. No se envía nada en este paso; los correos se mandan desde el panel de escritorio.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: rojo), onPressed: () => Navigator.pop(ctx, true), child: const Text('Validar y firmar')),
        ],
      ),
    );
    if (ok != true) return;
    final r = await _post('docsol_actares_firmar', {});
    if (r?['ok'] == true) {
      _aviso((r?['nota'] ?? 'Acta validada').toString());
      _cargar();
    } else {
      _aviso((r?['error'] ?? 'No se pudo validar').toString(), err: true);
    }
  }

  // ------------------------------------------------------------------ UI
  List<Map<String, dynamic>> _lista() {
    final l = ((_res?['lista'] as List?) ?? []).cast<Map<String, dynamic>>();
    final q = _busca.trim().toLowerCase();
    return l.where((x) {
      if (x['fuera'] == true) return _filtro == 'todos';
      final d = (x['decision'] ?? '').toString();
      if (_filtro == 'sinDictamen' && d.isNotEmpty) return false;
      if (_filtro != 'todos' && _filtro != 'sinDictamen' && d != _filtro) return false;
      if (q.isNotEmpty && !('${x['nombre']} ${x['folio']} ${x['asignatura']}'.toLowerCase().contains(q))) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: crema,
      appBar: AppBar(
        backgroundColor: rojo,
        foregroundColor: Colors.white,
        title: const Text('Fase 2 · Resultados y dictamen'),
        actions: [IconButton(tooltip: 'Actualizar', onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh))],
      ),
      body: _cargando && _res == null
          ? const Center(child: CircularProgressIndicator(color: rojo))
          : _pideClave
              ? _vistaClave()
              : _res == null
                  ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
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
                          _resumen(),
                          const SizedBox(height: 10),
                          _acta != null ? _tarjetaActa() : const SizedBox.shrink(),
                          const SizedBox(height: 10),
                          _filtros(),
                          const SizedBox(height: 8),
                          ..._lista().map(_tarjeta),
                          if (_lista().isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('Nadie con ese filtro.', textAlign: TextAlign.center, style: TextStyle(color: gris))),
                        ],
                      ),
                    ),
    );
  }

  Widget _vistaClave() => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.lock_outline, size: 48, color: oro),
          const SizedBox(height: 12),
          Text(_error, textAlign: TextAlign.center, style: const TextStyle(color: gris)),
          const SizedBox(height: 16),
          TextField(controller: _claveCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Clave del comité', border: OutlineInputBorder()), onSubmitted: (_) { _claveMemoria = _claveCtrl.text.trim(); _cargar(); }),
          const SizedBox(height: 12),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: rojo), onPressed: () { _claveMemoria = _claveCtrl.text.trim(); _cargar(); }, child: const Text('Entrar')),
        ]),
      );

  Widget _kpi(String n, String t, {Color? c}) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(color: Theme.of(context).cardColor, border: Border.all(color: linea), borderRadius: BorderRadius.circular(10)),
          child: Column(children: [
            Text(n, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c ?? const Color(0xFF2A2A2A))),
            Text(t, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: gris)),
          ]),
        ),
      );

  Widget _resumen() {
    final r = (_res!['resumen'] as Map<String, dynamic>?) ?? {};
    return Row(children: [
      _kpi('${r['aceptados'] ?? 0}', 'aceptados', c: verde),
      const SizedBox(width: 6),
      _kpi('${r['reserva'] ?? 0}', 'reserva', c: oro),
      const SizedBox(width: 6),
      _kpi('${r['noAceptados'] ?? 0}', 'no\naceptados', c: rojo),
      const SizedBox(width: 6),
      _kpi('${r['sinDictamen'] ?? 0}', 'sin\ndictamen', c: (r['sinDictamen'] ?? 0) == 0 ? verde : oro),
      const SizedBox(width: 6),
      _kpi('${r['conObservacion'] ?? 0}', 'con\nobservación'),
    ]);
  }

  Widget _tarjetaActa() {
    final a = _acta!;
    final firmas = (a['firmas'] as List?) ?? [];
    final completa = a['completa'] == true;
    final sin = (a['sinDictamen'] as List?)?.length ?? 0;
    final miCargo = _cargoDeActor();
    Map<String, dynamic>? mia;
    for (final f in firmas) {
      if (miCargo.isNotEmpty && (f['cargo'] ?? '').toString().toLowerCase() == miCargo.toLowerCase()) mia = f as Map<String, dynamic>;
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: completa ? verde.withOpacity(.07) : Colors.white,
        border: Border.all(color: completa ? verde.withOpacity(.5) : oro),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(completa ? Icons.verified : Icons.history_edu, color: completa ? verde : oro),
          const SizedBox(width: 8),
          Expanded(child: Text(completa ? 'Acta de resultados validada' : 'Acta de resultados: pendiente de validar', style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 6),
        Text('Huella ${(a['hash'] ?? '').toString().substring(0, ((a['hash'] ?? '').toString().length).clamp(0, 12))}… · basta una firma', style: const TextStyle(fontSize: 11.5, color: gris)),
        ...firmas.map((f) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                Icon(f['firmada'] == true ? Icons.check_circle : Icons.radio_button_unchecked, size: 16, color: f['firmada'] == true ? verde : gris),
                const SizedBox(width: 6),
                Expanded(child: Text('${f['cargo']}${f['firmada'] == true ? ' · ${f['fechaTxt']}' : (f['desactualizada'] == true ? ' · cambió, volver a firmar' : ' · pendiente')}', style: const TextStyle(fontSize: 12.5))),
              ]),
            )),
        const SizedBox(height: 8),
        if (sin > 0)
          Text('Faltan $sin dictámenes para poder validar.', style: const TextStyle(fontSize: 12, color: oro, fontWeight: FontWeight.w600))
        else if (mia != null && mia['firmada'] != true)
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: rojo),
            onPressed: _firmar,
            icon: const Icon(Icons.draw_outlined, size: 18),
            label: Text('Validar y firmar como ${mia['cargo']}'),
          )
        else
          const Text('Los correos de resultado (diplomado / avisos) se envían desde el panel de escritorio, con vista previa.', style: TextStyle(fontSize: 12, color: gris)),
      ]),
    );
  }

  // (8-oct) Ya no se reconoce el cargo por una clave escrita en la app: se usa la sesión del actor.
  String _cargoDeActor() {
    final a = widget.actor.trim().toLowerCase();
    if (a == 'vicerrectoria@cessum.mx') return 'Vicerrector Académico';
    if (a == 'rectoria@cessum.mx') return 'Rector';
    return '';
  }

  Widget _filtros() {
    final chips = <MapEntry<String, String>>[
      const MapEntry('todos', 'Todos'),
      const MapEntry('sinDictamen', 'Sin dictamen'),
      const MapEntry('Aceptado', 'Aceptados'),
      const MapEntry('Reserva', 'Reserva'),
      const MapEntry('No aceptado', 'No aceptados'),
    ];
    return Column(children: [
      TextField(
        decoration: InputDecoration(
          hintText: 'Buscar nombre, folio o asignatura…',
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
        child: Row(
          children: chips.map((c) {
            final act = _filtro == c.key;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(c.value),
                selected: act,
                selectedColor: rojoOsc,
                labelStyle: TextStyle(color: act ? Colors.white : const Color(0xFF4A4A4A), fontWeight: FontWeight.w600, fontSize: 12),
                onSelected: (_) => setState(() => _filtro = c.key),
              ),
            );
          }).toList(),
        ),
      ),
    ]);
  }

  String _num(dynamic v) => (v == null || v == '') ? '—' : v.toString();

  Widget _pill(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: c.withOpacity(.14), borderRadius: BorderRadius.circular(6)),
        child: Text(t, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: c)),
      );

  Widget _tarjeta(Map<String, dynamic> x) {
    final fuera = x['fuera'] == true;
    final dec = (x['decision'] ?? '').toString();
    final colorDec = dec == 'Aceptado' ? verde : (dec == 'Reserva' ? oro : (dec == 'No aceptado' ? rojo : gris));
    final com = x['comite'] as Map<String, dynamic>? ?? {};
    final obs = x['observadores'] as Map<String, dynamic>? ?? {};
    final ia = x['ia'] as Map<String, dynamic>?;
    final recs = (obs['recomendaciones'] as Map?)?.entries.map((e) => '${e.key} ${e.value}').join(', ') ?? '';
    return Opacity(
      opacity: fuera ? .55 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: dec.isEmpty ? Colors.white : colorDec.withOpacity(.06),
          border: Border(left: BorderSide(color: dec.isEmpty ? linea : colorDec, width: dec.isEmpty ? 1 : 4), top: const BorderSide(color: linea), right: const BorderSide(color: linea), bottom: const BorderSide(color: linea)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(x['nombre'].toString(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
              Text('${x['folio']} · ${x['grado']} · ${x['ciudad']}', style: const TextStyle(fontSize: 11.5, color: gris)),
              Text(fuera ? 'Fuera · plazo vencido' : '${x['diaNombre']} ${x['horaTxt']} · ${x['asignatura']}${(x['asistencia'] ?? '').toString().isNotEmpty ? ' · ${x['asistencia']}' : ''}',
                  style: TextStyle(fontSize: 11.5, color: fuera ? rojo : gris, fontWeight: fuera ? FontWeight.w700 : FontWeight.normal)),
            ])),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_num(x['integrado']), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: rojoOsc, height: 1)),
              Text(((x['integradoBase'] as List?) ?? []).join('+'), style: const TextStyle(fontSize: 9.5, color: gris)),
            ]),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 4, children: [
            _pill('comité ${_num(com['puntaje'])} (${com['cuantas'] ?? 0} val)', gris),
            _pill('observadores ${_num(obs['promedio'])} (${obs['cuantos'] ?? 0})${recs.isNotEmpty ? ' · $recs' : ''}', obs['promedio'] == null ? gris : verde),
            _pill('IA ${ia == null ? '—' : _num(ia['puntaje'])}${ia != null && (ia['recomienda'] ?? '').toString().isNotEmpty ? ' · ${ia['recomienda']}' : ''}', oro),
          ]),
          if (dec.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                _pill(dec.toUpperCase(), colorDec),
                const SizedBox(width: 6),
                Expanded(child: Text((x['decisionMotivo'] ?? '').toString().isNotEmpty ? x['decisionMotivo'].toString() : '${x['decisionQuien']} · ${x['decisionCuando']}', style: const TextStyle(fontSize: 11.5, color: gris), overflow: TextOverflow.ellipsis, maxLines: 2)),
                if ((x['avisadoEl'] ?? '').toString().isNotEmpty) _pill('avisado', verde),
              ]),
            ),
          if (!fuera && (x['avisadoEl'] ?? '').toString().isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                _btnDec('Aceptado', verde, x, dec),
                _btnDec('Reserva', oro, x, dec),
                _btnDec('No aceptado', rojo, x, dec),
                if (dec.isNotEmpty) TextButton(onPressed: () => _dictaminar(x, ''), child: const Text('Quitar', style: TextStyle(fontSize: 12, color: gris))),
                IconButton(
                  tooltip: 'Copiar enlace al reporte PDF (panel)',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: 'https://cessum.mx/admin-docentes.php?reporte_pdf=${x['folio']}'));
                    _aviso('Enlace del reporte copiado (se abre con sesión del panel).');
                  },
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 20, color: gris),
                ),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _btnDec(String d, Color c, Map<String, dynamic> x, String actual) {
    final sel = actual == d;
    return sel
        ? FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: const Size(0, 34), textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            onPressed: () => _dictaminar(x, d),
            child: Text(d),
          )
        : OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: c, side: BorderSide(color: c.withOpacity(.6)), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: const Size(0, 34), textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            onPressed: () => _dictaminar(x, d),
            child: Text(d),
          );
  }
}
