// =====================================================================
//  titulacion_motor_screen.dart · CESSUM · (25-sep-2026)
//  MOTOR DE TITULACIÓN (administración)
//
//  La titulación se detenía porque nada la empujaba. Aquí se ve, por cada
//  expediente, QUIÉN tiene la pelota (CESSUM, el alumno o la SEC), cuál es
//  el siguiente paso y cuántos días lleva parado, y se resuelve en bloque:
//   · Avanzar los expedientes listos (correo al alumno con su nueva etapa).
//   · Emitir kárdex y constancia de no adeudo (la constancia solo si el
//     alumno está al corriente); quedan aprobados en el expediente.
//   · Recordar a los alumnos lo que les falta (primero en modo prueba).
//   · Documentos con IA: sugerencia de aprobar/rechazar cada documento
//     «En revisión», con sus hallazgos.
//  Toda acción masiva muestra primero a quién le llegaría y qué.
//
//  Guardián: GET titulacion_motor · GET titulacion_ia_pendientes
//            POST titulacion_motor_avanzar · POST titulacion_motor_emitir
//            POST titulacion_recordar · POST titulacion_actualizar
// =====================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';

const _verde = Color(0xFF1E7F52);

class TitulacionMotorScreen extends StatefulWidget {
  const TitulacionMotorScreen({super.key});
  @override
  State<TitulacionMotorScreen> createState() => _TitulacionMotorScreenState();
}

class _TitulacionMotorScreenState extends State<TitulacionMotorScreen> {
  bool _cargando = true;
  String _error = '';
  List<Map<String, dynamic>> _items = [];
  Map<String, dynamic> _resumen = {};
  String _filtro = 'todo';
  bool _ocupado = false;

  // Documentos con IA
  bool _cargandoIa = false;
  bool _iaCargada = false;
  String _errorIa = '';
  List<Map<String, dynamic>> _docs = [];
  int _quedan = 0;
  final Set<String> _resueltos = {};

  static const _nombres = {
    'avanzar': 'Listos para avanzar',
    'emitir': 'CESSUM debe emitir',
    'revisar': 'Documentos por revisar',
    'recordar': 'Esperando al alumno',
    'sinodos': 'Asignar sínodos',
    'examen': 'Examen',
    'entrega': 'Programar entrega',
    'SEC': 'En la SEC',
    'Concluido': 'Concluidos',
    'Cerrado': 'Cerrados',
  };

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<Map<String, dynamic>> _get(Map<String, String> qp, {int segundos = 90}) async {
    final r = await http.get(Uri.parse(guardianUrl).replace(queryParameters: qp)).timeout(Duration(seconds: segundos));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _post(Map<String, dynamic> body, {int segundos = 120}) async {
    final r = await http
        .post(Uri.parse(guardianUrl), headers: {'Content-Type': 'text/plain;charset=utf-8'}, body: jsonEncode(body))
        .timeout(Duration(seconds: segundos));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  void _aviso(String t, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: error ? cessumRed : _verde,
      duration: const Duration(seconds: 6),
      content: Text(t),
    ));
  }

  String _clave(Map<String, dynamic> x) {
    final a = '${x['accion'] ?? ''}';
    return a.isNotEmpty ? a : '${x['responsable'] ?? ''}';
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final d = await _get({'accion': 'titulacion_motor'});
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo cargar.');
      _items = ((d['items'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _resumen = Map<String, dynamic>.from((d['resumen'] as Map?) ?? {});
    } catch (e) {
      _error = '$e'.replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _cargando = false);
  }

  // ---------------- Acciones en bloque ----------------

  Future<bool> _confirmar(String titulo, Widget contenido, String boton) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo, style: const TextStyle(fontSize: 17)),
        content: SizedBox(width: 520, child: SingleChildScrollView(child: contenido)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(boton),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _avanzar() async {
    setState(() => _ocupado = true);
    try {
      final pre = await _post({'accion': 'titulacion_motor_avanzar'});
      if (pre['ok'] != true) throw Exception(pre['error'] ?? 'No se pudo preparar.');
      final plan = ((pre['plan'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!mounted) return;
      if (plan.isEmpty) {
        _aviso('No hay expedientes listos para avanzar.');
      } else if (await _confirmar(
          '¿Avanzar ${plan.length} expediente(s)?',
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Se enviarán ${pre['correos']} correo(s) a los alumnos: ${pre['nota']}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cessumRed)),
            const SizedBox(height: 10),
            for (final p in plan)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('• ${p['nombre']}: ${p['de']} → ${p['a']}', style: const TextStyle(fontSize: 13, height: 1.35)),
              ),
          ]),
          'Avanzar y avisar')) {
        final d = await _post({'accion': 'titulacion_motor_avanzar', 'confirmar': true}, segundos: 320);
        if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo avanzar.');
        _aviso('Avanzados: ${d['avanzados']} expediente(s).');
        await _cargar();
      }
    } catch (e) {
      if (mounted) _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _ocupado = false);
  }

  Future<void> _emitir() async {
    setState(() => _ocupado = true);
    try {
      final pre = await _post({'accion': 'titulacion_motor_emitir'});
      if (pre['ok'] != true) throw Exception(pre['error'] ?? 'No se pudo preparar.');
      final plan = ((pre['plan'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final listos = plan.where((p) => '${p['bloqueado'] ?? ''}'.isEmpty).length;
      if (!mounted) return;
      if (plan.isEmpty) {
        _aviso('No hay documentos por emitir.');
      } else if (await _confirmar(
          '¿Emitir $listos documento(s)?',
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${pre['nota']}', style: const TextStyle(fontSize: 13, height: 1.4)),
            const SizedBox(height: 10),
            for (final p in plan)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '• ${p['nombre']}: ${p['etiqueta']}'
                  '${'${p['bloqueado'] ?? ''}'.isNotEmpty ? ' — NO se emite: ${p['bloqueado']}' : ''}',
                  style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: '${p['bloqueado'] ?? ''}'.isNotEmpty ? cessumRed : null),
                ),
              ),
            const SizedBox(height: 6),
            const Text('Cada documento tarda unos segundos: con muchos, puede tomar un par de minutos.',
                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey)),
          ]),
          'Emitir')) {
        final d = await _post({'accion': 'titulacion_motor_emitir', 'confirmar': true}, segundos: 320);
        if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo emitir.');
        final pend = (d['pendientes'] ?? 0) as num;
        _aviso('Emitidos: ${d['emitidos']} documento(s).${pend > 0 ? ' Quedaron $pend por tiempo: vuelva a tocar «Emitir».' : ''}');
        await _cargar();
      }
    } catch (e) {
      if (mounted) _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _ocupado = false);
  }

  Future<void> _recordar() async {
    setState(() => _ocupado = true);
    try {
      final pre = await _post({'accion': 'titulacion_recordar', 'prueba': true});
      if (pre['ok'] != true) throw Exception(pre['error'] ?? 'No se pudo preparar.');
      final dest = ((pre['destinatarios'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final ejemplo = '${pre['ejemplo'] ?? ''}'
          .replaceAll(RegExp(r'<li>'), '\n• ')
          .replaceAll(RegExp(r'</p>|<br>'), '\n')
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .replaceAll('&gt;', '>')
          .replaceAll(RegExp(r'\n{3,}'), '\n\n')
          .trim();
      if (!mounted) return;
      if (dest.isEmpty) {
        _aviso('Nadie necesita recordatorio ahora (o ya se le envió en los últimos 7 días).');
      } else if (await _confirmar(
          '¿Enviar ${dest.length} recordatorio(s)?',
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Le llegaría un correo y un aviso en la app a ${dest.length} alumno(s), como máximo uno cada 7 días:',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cessumRed)),
            const SizedBox(height: 8),
            for (final x in dest)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text('• ${x['nombre']} (${x['correo']}) · ${x['dias'] ?? '—'} días · falta: ${((x['faltan'] as List?) ?? []).join(', ')}',
                    style: const TextStyle(fontSize: 12.5, height: 1.35)),
              ),
            const SizedBox(height: 10),
            const Text('Así se ve el correo (primer alumno):', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: cessumGold.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
              child: Text(ejemplo, style: const TextStyle(fontSize: 12.5, height: 1.4)),
            ),
          ]),
          'Enviar recordatorios')) {
        final d = await _post({'accion': 'titulacion_recordar', 'prueba': false}, segundos: 200);
        if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo enviar.');
        _aviso('Recordatorios enviados: ${d['enviados']} de ${d['total']}.');
      }
    } catch (e) {
      if (mounted) _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
    if (mounted) setState(() => _ocupado = false);
  }

  // ---------------- Documentos con IA ----------------

  Future<void> _cargarIa() async {
    setState(() {
      _cargandoIa = true;
      _errorIa = '';
    });
    try {
      final d = await _get({'accion': 'titulacion_ia_pendientes'}, segundos: 280);
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo revisar.');
      _docs = ((d['items'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _quedan = ((d['quedanSinRevisar'] ?? 0) as num).toInt();
      _iaCargada = true;
    } catch (e) {
      _errorIa = '$e'.replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _cargandoIa = false);
  }

  Future<void> _resolverDoc(Map<String, dynamic> x, bool aprobar) async {
    final hall = ((x['hallazgos'] as List?) ?? []).map((e) => '$e').toList();
    final obs = TextEditingController(text: aprobar ? '' : hall.join(' '));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(aprobar ? '¿Aprobar el documento?' : 'Rechazar el documento', style: const TextStyle(fontSize: 17)),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${x['nombre']} · ${x['etiqueta']}', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('Al alumno le llega un correo con el resultado, como siempre.',
                style: TextStyle(fontSize: 12.5, color: Colors.grey)),
            const SizedBox(height: 10),
            TextField(
              controller: obs,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                isDense: true,
                labelText: aprobar ? 'Observación (opcional)' : 'Motivo para el alumno (obligatorio)',
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: aprobar ? _verde : cessumRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(aprobar ? 'Aprobar' : 'Rechazar'),
          ),
        ],
      ),
    );
    final texto = obs.text.trim();
    obs.dispose();
    if (ok != true || !mounted) return;
    if (!aprobar && texto.isEmpty) {
      _aviso('Escriba el motivo del rechazo: se le envía al alumno.', error: true);
      return;
    }
    final clave = '${x['folio']}|${x['tipo']}';
    try {
      final d = await _post({
        'accion': 'titulacion_actualizar',
        'folio': x['folio'],
        'docTipo': x['tipo'],
        'docEstatus': aprobar ? 'Aprobado' : 'Rechazado',
        'observacion': texto,
      }, segundos: 90);
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo guardar.');
      setState(() => _resueltos.add(clave));
      _aviso(aprobar ? 'Documento aprobado.' : 'Documento rechazado; el alumno recibió el motivo.');
    } catch (e) {
      _aviso('$e'.replaceFirst('Exception: ', ''), error: true);
    }
  }

  // ---------------- Vista ----------------

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: cessumBg(context),
        appBar: AppBar(
          backgroundColor: cessumRed,
          foregroundColor: Colors.white,
          title: const Text('Motor de titulación'),
          actions: [IconButton(tooltip: 'Actualizar', onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh))],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [Tab(text: 'Expedientes'), Tab(text: 'Documentos con IA')],
          ),
        ),
        body: TabBarView(children: [_tabExpedientes(), _tabDocumentos()]),
      ),
    );
  }

  Widget _tabExpedientes() {
    if (_cargando) return const Center(child: CircularProgressIndicator(color: cessumRed));
    if (_error.isNotEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_error, textAlign: TextAlign.center),
        TextButton(onPressed: _cargar, child: const Text('Reintentar')),
      ]));
    }
    final n = (String k) => ((_resumen[k] ?? 0) as num).toInt();
    final vis = _filtro == 'todo' ? _items : _items.where((x) => _clave(x) == _filtro).toList();
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(padding: const EdgeInsets.all(14), children: [
        Text(
          'Quién tiene la pelota en cada expediente y cuál es su siguiente paso. Las acciones en bloque muestran primero '
          'a quién le llegaría y qué.',
          style: TextStyle(fontSize: 12.5, height: 1.45, color: cessumMuted(context)),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _verde),
            onPressed: _ocupado || n('avanzar') == 0 ? null : _avanzar,
            icon: const Icon(Icons.fast_forward, size: 18),
            label: Text('Avanzar listos (${n('avanzar')})'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: _ocupado || n('emitir') == 0 ? null : _emitir,
            icon: const Icon(Icons.description_outlined, size: 18),
            label: Text('Emitir kárdex y no adeudo (${n('emitir')})'),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: cessumRed),
            onPressed: _ocupado ? null : _recordar,
            icon: const Icon(Icons.notifications_active_outlined, size: 18),
            label: const Text('Recordar a alumnos'),
          ),
        ]),
        if (_ocupado)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: LinearProgressIndicator(color: cessumRed),
          ),
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: [
          ChoiceChip(
            label: Text('Todos (${_items.length})'),
            selected: _filtro == 'todo',
            onSelected: (_) => setState(() => _filtro = 'todo'),
          ),
          for (final k in _nombres.keys)
            if (n(k) > 0)
              ChoiceChip(
                label: Text('${_nombres[k]} (${n(k)})'),
                selected: _filtro == k,
                onSelected: (_) => setState(() => _filtro = k),
              ),
        ]),
        const SizedBox(height: 10),
        if (vis.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Center(child: Text('Nada en esta vista.', style: TextStyle(color: cessumMuted(context)))),
          )
        else
          ...vis.map(_tarjeta),
      ]),
    );
  }

  Widget _tarjeta(Map<String, dynamic> x) {
    final k = _clave(x);
    final quien = '${x['responsable']}';
    final Color c = k == 'avanzar'
        ? _verde
        : quien == 'Alumno'
            ? cessumGold
            : quien == 'SEC' || quien == 'Concluido' || quien == 'Cerrado'
                ? Colors.grey
                : cessumRed;
    final faltan = ((x['faltaAlumno'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final dias = x['dias'];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${x['nombre']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Text(quien == 'CESSUM' ? 'Le toca a CESSUM' : quien == 'Alumno' ? 'Le toca al alumno' : quien,
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
          ),
        ]),
        Text('${x['matricula']} · ${x['opcion']} · ${x['etapa']}${dias != null ? ' · $dias días sin moverse' : ''}',
            style: TextStyle(
                fontSize: 11.5,
                color: (dias is num && dias >= 14 && quien != 'SEC') ? cessumRed : cessumMuted(context),
                fontWeight: (dias is num && dias >= 14 && quien != 'SEC') ? FontWeight.w700 : FontWeight.w400)),
        const SizedBox(height: 6),
        Text('Siguiente: ${x['siguiente']}', style: const TextStyle(fontSize: 13, height: 1.35, fontWeight: FontWeight.w600)),
        if (quien != 'Alumno' && faltan.where((f) => f['informativo'] != true).isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Al alumno también le falta: ${faltan.where((f) => f['informativo'] != true).map((f) => f['etiqueta']).join(', ')}',
              style: const TextStyle(fontSize: 12, color: cessumGold, fontWeight: FontWeight.w600),
            ),
          ),
      ]),
    );
  }

  Widget _tabDocumentos() {
    final pendientes = _docs.where((x) => !_resueltos.contains('${x['folio']}|${x['tipo']}')).toList();
    return ListView(padding: const EdgeInsets.all(14), children: [
      Text(
        'La IA revisa cada documento «En revisión»: que sea el documento correcto, que se lea, que el nombre y la CURP '
        'coincidan con el expediente y, en el comprobante, el monto y la cuenta. Solo sugiere: usted decide.',
        style: TextStyle(fontSize: 12.5, height: 1.45, color: cessumMuted(context)),
      ),
      const SizedBox(height: 10),
      FilledButton.icon(
        style: FilledButton.styleFrom(backgroundColor: cessumRed),
        onPressed: _cargandoIa ? null : _cargarIa,
        icon: _cargandoIa
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.auto_awesome, size: 18),
        label: Text(_cargandoIa
            ? 'Revisando… (puede tardar 1-3 min)'
            : _iaCargada
                ? 'Revisar de nuevo'
                : 'Revisar documentos con IA'),
      ),
      if (_errorIa.isNotEmpty)
        Padding(padding: const EdgeInsets.only(top: 10), child: Text(_errorIa, style: const TextStyle(color: cessumRed))),
      if (_quedan > 0)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('Quedan $_quedan documento(s) sin revisar: toque «Revisar de nuevo» para continuar.',
              style: const TextStyle(fontSize: 12.5, color: cessumGold, fontWeight: FontWeight.w600)),
        ),
      const SizedBox(height: 12),
      if (_iaCargada && pendientes.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 30),
          child: Center(child: Text('No hay documentos en revisión.', style: TextStyle(color: cessumMuted(context)))),
        ),
      for (final x in pendientes) _tarjetaDoc(x),
    ]);
  }

  Widget _tarjetaDoc(Map<String, dynamic> x) {
    final sug = '${x['sugerencia'] ?? ''}';
    final hall = ((x['hallazgos'] as List?) ?? []).map((e) => '$e').toList();
    final Color c = sug == 'Aprobado'
        ? _verde
        : sug == 'Rechazado'
            ? cessumRed
            : sug == 'Revisar'
                ? cessumGold
                : Colors.grey;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${x['etiqueta']}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Text(
                x['sinRevisar'] == true
                    ? 'Sin revisar'
                    : sug == 'Aprobado'
                        ? 'IA: aprobar'
                        : sug == 'Rechazado'
                            ? 'IA: rechazar'
                            : 'IA: revisar',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c)),
          ),
        ]),
        Text('${x['nombre']} · ${x['matricula']} · ${x['etapa']}', style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
        for (final h in hall)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('• $h', style: TextStyle(fontSize: 12.5, height: 1.35, color: c == Colors.grey ? null : c)),
          ),
        if (sug == 'Aprobado' && hall.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Coincide con el expediente.', style: TextStyle(fontSize: 12.5, color: _verde)),
          ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: cessumRed, visualDensity: VisualDensity.compact),
            onPressed: () => launchUrl(Uri.parse('${x['url']}'), webOnlyWindowName: '_blank'),
            icon: const Icon(Icons.visibility_outlined, size: 16),
            label: const Text('Ver documento'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _verde, visualDensity: VisualDensity.compact),
            onPressed: () => _resolverDoc(x, true),
            child: const Text('Aprobar'),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: cessumRed, visualDensity: VisualDensity.compact),
            onPressed: () => _resolverDoc(x, false),
            child: const Text('Rechazar'),
          ),
        ]),
      ]),
    );
  }
}
