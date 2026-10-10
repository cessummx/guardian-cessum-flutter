// BAJAS POR PAGO · BANDEJA DE AUTORIZACIÓN (22-sep-2026)
//
// Regla: el corte se cuenta en materias (3 en la Maestría en Educación, 4 en
// maestrías y doctorados en línea, por periodo en mixta, por cuatrimestre en
// licenciatura). Cada corte cerrado exige su parte de colegiaturas, la
// inscripción y las reinscripciones. 30 días de gracia; «por validar» cuenta
// como pagado; un solo pago faltante basta.
// Nada se ejecuta solo: aquí se autoriza, se pospone o se descarta. Autorizar
// deja la solicitud PENDIENTE en Bajas; el acta y el correo al alumno salen
// hasta que se valida allí.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';

class BajasPagoScreen extends StatefulWidget {
  const BajasPagoScreen({super.key});
  @override
  State<BajasPagoScreen> createState() => _BajasPagoScreenState();
}

class _BajasPagoScreenState extends State<BajasPagoScreen> {
  String _actor = '';
  bool _cargando = true;
  String _error = '';
  Map<String, dynamic> _d = {};
  bool _todos = false;
  final _cBuscar = TextEditingController();

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  @override
  void dispose() {
    _cBuscar.dispose();
    super.dispose();
  }

  Future<void> _iniciar() async {
    // (24-sep) Correo REAL: en «Ver como profesor» el de la vista es el del profesor.
    _actor = ((await SessionStore.realEmail()) ?? '').trim().toLowerCase();
    _cargar();
  }

  Future<Map<String, dynamic>> _get(Map<String, String> qp) async {
    final r = await http
        .get(Uri.parse(guardianUrl).replace(queryParameters: {...qp, 'actor': _actor}))
        .timeout(const Duration(seconds: 180));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> _cargar({bool refrescar = false}) async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final d = await _get({
        'accion': 'bajas_pago_bandeja',
        if (refrescar) 'refrescar': '1',
        if (_todos) 'todos': '1',
      });
      if (!mounted) return;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo consultar');
      setState(() {
        _d = d;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  static String _m(dynamic v) {
    final x = (v is num ? v : num.tryParse('$v') ?? 0).round();
    final s = x.abs().toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return '\$$b';
  }

  Future<void> _decidir(Map<String, dynamic> a, String decision) async {
    final cMotivo = TextEditingController();
    DateTime? hasta;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) {
        final titulo = decision == 'autorizar'
            ? 'Autorizar la baja'
            : decision == 'posponer'
                ? 'Posponer'
                : 'Descartar';
        return AlertDialog(
          title: Text(titulo, style: const TextStyle(fontSize: 16)),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${a['nombre']} · ${a['matricula']}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              if (decision == 'autorizar')
                const Text(
                    'La solicitud entra PENDIENTE a la bandeja de Bajas. Hasta que se valide allí '
                    'se emiten el acta y el correo al alumno. Aquí no se envía nada.',
                    style: TextStyle(fontSize: 12.5)),
              if (decision == 'posponer') ...[
                const Text('Por ejemplo, por un convenio de pago. Vuelve a aparecer después de esa fecha.',
                    style: TextStyle(fontSize: 12.5)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event, size: 18),
                  label: Text(hasta == null
                      ? 'Elegir fecha'
                      : '${hasta!.day.toString().padLeft(2, '0')}/${hasta!.month.toString().padLeft(2, '0')}/${hasta!.year}'),
                  onPressed: () async {
                    final f = await showDatePicker(
                      context: ctx2,
                      initialDate: DateTime.now().add(const Duration(days: 30)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (f != null) setD(() => hasta = f);
                  },
                ),
              ],
              if (decision == 'descartar')
                const Text('Deja de aparecer en este corte. Indique el motivo: beca, error de registro, pago en efectivo…',
                    style: TextStyle(fontSize: 12.5)),
              const SizedBox(height: 8),
              TextField(
                controller: cMotivo,
                maxLines: 2,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: decision == 'descartar' ? 'Motivo (obligatorio)' : 'Nota (opcional)',
                  border: const OutlineInputBorder(),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx2, false), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: decision == 'autorizar' ? cessumRed : cessumGold),
              onPressed: () {
                if (decision == 'posponer' && hasta == null) return;
                if (decision == 'descartar' && cMotivo.text.trim().isEmpty) return;
                Navigator.pop(ctx2, true);
              },
              child: Text(titulo),
            ),
          ],
        );
      }),
    );
    if (ok != true) return;
    try {
      final r = await _get({
        'accion': 'bajas_pago_decidir',
        'matricula': '${a['matricula']}',
        'programa': '${a['programa']}',
        'corte': '${a['cortesVencidos']}',
        'decision': decision,
        if (hasta != null)
          'hasta':
              '${hasta!.year}-${hasta!.month.toString().padLeft(2, '0')}-${hasta!.day.toString().padLeft(2, '0')}',
        if (cMotivo.text.trim().isNotEmpty) 'motivo': cMotivo.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r['ok'] == true ? (r['nota'] ?? 'Listo.').toString() : 'No se pudo: ${r['error']}'),
        backgroundColor: r['ok'] == true ? const Color(0xFF1E7F52) : cessumRed,
      ));
      if (r['ok'] == true) _cargar(refrescar: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo: $e'), backgroundColor: cessumRed));
    }
  }

  @override
  Widget build(BuildContext context) {
    final todos = ((_d['alumnos'] as List?) ?? []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
    final q = _cBuscar.text.trim().toLowerCase();
    final lista = todos
        .where((a) =>
            q.isEmpty ||
            '${a['nombre']} ${a['matricula']} ${a['programa']} ${a['generacion']}'.toLowerCase().contains(q))
        .toList();
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Bajas por pago'),
        actions: [
          IconButton(
            tooltip: 'Volver a calcular',
            onPressed: _cargando ? null : () => _cargar(refrescar: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _cargando
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(color: cessumRed),
                  SizedBox(height: 14),
                  Text('Cruzando materias cursadas con pagos registrados…', textAlign: TextAlign.center),
                ]),
              ),
            )
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.cloud_off, size: 42, color: cessumGold),
                      const SizedBox(height: 12),
                      Text(_error, textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: cessumRed),
                        onPressed: () => _cargar(),
                        child: const Text('Reintentar'),
                      ),
                    ]),
                  ),
                )
              : ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 30), children: [
                  _tarjeta(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${_d['total'] ?? 0} alumno(s) con pagos incompletos al corte',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(
                      'Revisados ${_d['revisados'] ?? 0} alumnos con al menos un corte cerrado hace más de '
                      '${(_d['reglas'] as Map?)?['graciaDias'] ?? 30} días. Los pagos «por validar» y las becas '
                      'ya están considerados. Medido el ${_d['generado'] ?? ''}'
                      '${_d['deCache'] == true ? ' (guardado; el botón de arriba lo recalcula)' : ''}.',
                      style: TextStyle(fontSize: 12, color: cessumMuted(context)),
                    ),
                    Row(children: [
                      Switch(
                        value: _todos,
                        activeColor: cessumRed,
                        onChanged: (v) {
                          setState(() => _todos = v);
                          _cargar();
                        },
                      ),
                      const Expanded(
                          child: Text('Incluir los ya autorizados, pospuestos o descartados',
                              style: TextStyle(fontSize: 12.5))),
                    ]),
                  ])),
                  TextField(
                    controller: _cBuscar,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Buscar por nombre, matrícula, programa o generación',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  if (lista.isEmpty)
                    _tarjeta(const Text('Nadie en la bandeja. Todos los cortes vencidos están cubiertos.'))
                  else
                    ...lista.map(_alumno),
                ]),
    );
  }

  Widget _tarjeta(Widget hijo, {Color? borde}) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: (borde ?? cessumGold).withValues(alpha: 0.35)),
        ),
        child: hijo,
      );

  Widget _alumno(Map<String, dynamic> a) {
    final dec = (a['decision'] ?? '').toString();
    final detalle = a['decisionDetalle'] is Map ? Map<String, dynamic>.from(a['decisionDetalle']) : null;
    final beca = a['beca'] is Map ? Map<String, dynamic>.from(a['beca']) : null;
    final faltanC = (a['faltanColegiaturas'] as num?)?.toInt() ?? 0;
    final faltanR = (a['faltanReinscripciones'] as num?)?.toInt() ?? 0;
    return _tarjeta(
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('${a['nombre']}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          ),
          Text('${a['matricula']}', style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
        ]),
        Text('${a['programa']} ${a['generacion']} · ${a['grupo']}',
            style: TextStyle(fontSize: 12, color: cessumMuted(context))),
        const SizedBox(height: 8),
        Text(
          'Faltan ${faltanC > 0 ? '$faltanC colegiatura(s)' : ''}'
          '${faltanC > 0 && faltanR > 0 ? ' y ' : ''}'
          '${faltanR > 0 ? '$faltanR reinscripción(es)' : ''} · ${_m(a['faltaPesos'])}',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: cessumRed),
        ),
        const SizedBox(height: 4),
        Text(
          '${a['materiasCursadas']} materias cursadas · corte cada ${a['materiasPorCorte']} · '
          '${a['cortesVencidos']} corte(s) vencido(s), el último cerrado el ${a['cierreCorte']}.\n'
          'Exigido ${_m(a['exigido'])} (${a['pagosPorCorte']} colegiatura(s) de ${_m(a['mensualidad'])} por corte, '
          'más inscripción) · Pagado ${_m(a['pagado'])} en ${a['comprobantes']} comprobante(s) · '
          'Reinscripciones ${a['reinsPagadas']} de ${a['reinsExigidas']}.\n'
          'Último pago: ${(a['ultimoPago'] ?? '').toString().isEmpty ? 'sin registro' : a['ultimoPago']}.'
          '${beca != null ? ' Con beca del ${beca['porcentaje']} %, ya aplicada.' : ''}'
          '${(a['solicitudBaja'] ?? '').toString().isNotEmpty ? ' Ya tiene una solicitud de baja: ${a['solicitudBaja']}.' : ''}',
          style: const TextStyle(fontSize: 12.5, height: 1.4),
        ),
        if (dec.isNotEmpty && detalle != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Decisión: ${detalle['decision']}'
              '${(detalle['hasta'] ?? '').toString().isNotEmpty ? ' hasta ${detalle['hasta']}' : ''}'
              '${(detalle['motivo'] ?? '').toString().isNotEmpty ? ' · ${detalle['motivo']}' : ''}',
              style: TextStyle(fontSize: 12, color: cessumMuted(context), fontStyle: FontStyle.italic),
            ),
          ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 6, children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: dec == 'autorizada' ? null : () => _decidir(a, 'autorizar'),
            icon: const Icon(Icons.gavel, size: 18),
            label: const Text('Autorizar baja'),
          ),
          OutlinedButton.icon(
            onPressed: () => _decidir(a, 'posponer'),
            icon: const Icon(Icons.schedule, size: 18),
            label: const Text('Posponer'),
          ),
          OutlinedButton.icon(
            onPressed: () => _decidir(a, 'descartar'),
            icon: const Icon(Icons.close, size: 18),
            label: const Text('Descartar'),
          ),
        ]),
      ]),
      borde: dec.isEmpty ? cessumRed : Colors.grey,
    );
  }
}
