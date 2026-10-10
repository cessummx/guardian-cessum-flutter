// =====================================================================
//  mi_ruta_screen.dart · CESSUM · (25-sep-2026)
//  MI RUTA AL TÍTULO (alumno)
//
//  «Mis pendientes» dice qué toca hoy; esta pantalla dice DÓNDE VA el
//  alumno y QUÉ LE FALTA para titularse, en siete etapas: materias,
//  reprobadas (y cómo recuperarlas), pagos, datos y documentos, opción de
//  titulación (elegibilidad y costo), trámite y título. Cada etapa lleva a
//  la pantalla donde se resuelve. Arriba, «Lo más importante ahora» y un
//  coach con IA que responde solo con sus datos.
//
//  Guardián: GET mi_ruta&matricula= · GET mi_ruta_ia&matricula=&pregunta=
// =====================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'student_profile.dart';
import 'auth/session_store.dart';
import 'avance_plan_screen.dart';
import 'recursamientos_screen.dart';
import 'mis_pendientes_screen.dart';
import 'about_screen.dart';
import 'mi_titulacion_screen.dart';

const _verde = Color(0xFF1E7F52);

class MiRutaScreen extends StatefulWidget {
  const MiRutaScreen({super.key});
  @override
  State<MiRutaScreen> createState() => _MiRutaScreenState();
}

class _MiRutaScreenState extends State<MiRutaScreen> {
  bool _cargando = true;
  String _error = '';
  Map<String, dynamic> _r = {};
  StudentProfile? _perfil;
  String _correo = '';

  // Coach
  bool _coachCargando = false;
  String _coach = '';
  String _coachError = '';
  final _pregunta = TextEditingController();
  bool _preguntando = false;
  String _respuesta = '';

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _pregunta.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _get(Map<String, String> qp, {int segundos = 120}) async {
    final r = await http.get(Uri.parse(guardianUrl).replace(queryParameters: qp)).timeout(Duration(seconds: segundos));
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      final p = await StudentProfile.load();
      if (p == null) throw Exception('Completa tu perfil para ver tu ruta.');
      _perfil = p;
      _correo = await SessionStore.validEmail() ?? '';
      final d = await _get({'accion': 'mi_ruta', 'matricula': p.matricula});
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo cargar tu ruta.');
      _r = d;
    } catch (e) {
      _error = '$e'.replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _cargando = false);
    if (_error.isEmpty && _coach.isEmpty) _cargarCoach();
  }

  Future<void> _cargarCoach() async {
    final p = _perfil;
    if (p == null) return;
    setState(() {
      _coachCargando = true;
      _coachError = '';
    });
    try {
      final d = await _get({'accion': 'mi_ruta_ia', 'matricula': p.matricula}, segundos: 150);
      if (d['ok'] != true) throw Exception(d['error'] ?? 'Tu coach no está disponible por ahora.');
      _coach = '${d['texto'] ?? ''}';
    } catch (e) {
      _coachError = '$e'.replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _coachCargando = false);
  }

  Future<void> _preguntar() async {
    final p = _perfil;
    final q = _pregunta.text.trim();
    if (p == null || q.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _preguntando = true;
      _respuesta = '';
    });
    try {
      final d = await _get({'accion': 'mi_ruta_ia', 'matricula': p.matricula, 'pregunta': q}, segundos: 150);
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo responder.');
      _respuesta = '${d['texto'] ?? ''}';
    } catch (e) {
      _respuesta = '$e'.replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _preguntando = false);
  }

  Future<void> _ir(String destino) async {
    final p = _perfil;
    if (p == null) return;
    Widget? pantalla;
    switch (destino) {
      case 'avance':
        pantalla = const AvancePlanScreen();
        break;
      case 'recursamientos':
        pantalla = RecursamientosScreen(
          matricula: p.matricula,
          correo: _correo,
          nombre: p.nombreCompleto,
          programa: p.programa,
          generacion: p.generacion,
        );
        break;
      case 'pendientes':
        pantalla = MisPendientesScreen(matricula: p.matricula, nombre: p.nombreCompleto, correo: _correo);
        break;
      case 'perfil':
        pantalla = const AboutScreen();
        break;
      case 'titulacion':
        pantalla = const MiTitulacionScreen();
        break;
    }
    if (pantalla == null) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla!));
    if (mounted) _cargar();
  }

  String _pesos(dynamic v) {
    final n = num.tryParse('${v ?? ''}'.replaceAll(RegExp(r'[^\d.]'), ''));
    if (n == null || n == 0) return '';
    final t = n.round().toString();
    final b = StringBuffer();
    for (var i = 0; i < t.length; i++) {
      if (i > 0 && (t.length - i) % 3 == 0) b.write(',');
      b.write(t[i]);
    }
    return '\$$b';
  }

  static const _textoIr = {
    'avance': 'Ver avance de mi plan',
    'recursamientos': 'Ir a Recursamientos',
    'pendientes': 'Ver mis pagos',
    'perfil': 'Completar mi perfil',
    'titulacion': 'Ir a Mi titulación',
  };

  // ---------------- Vista ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Mi ruta al título'),
        actions: [IconButton(tooltip: 'Actualizar', onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh))],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_error, textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      TextButton(onPressed: _cargar, child: const Text('Reintentar')),
                    ]),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _cargar,
                  child: ListView(padding: const EdgeInsets.all(14), children: [
                    _encabezado(),
                    const SizedBox(height: 12),
                    if (_r['ahora'] is Map) _tarjetaAhora(Map<String, dynamic>.from(_r['ahora'] as Map)),
                    const SizedBox(height: 12),
                    _tarjetaCoach(),
                    const SizedBox(height: 16),
                    Text('TU RUTA', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1, color: cessumMuted(context))),
                    const SizedBox(height: 8),
                    ..._hitos().asMap().entries.map((e) => _hito(e.value, e.key == _hitos().length - 1)),
                    const SizedBox(height: 20),
                  ]),
                ),
    );
  }

  List<Map<String, dynamic>> _hitos() =>
      ((_r['hitos'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  Widget _encabezado() {
    final al = Map<String, dynamic>.from((_r['alumno'] as Map?) ?? {});
    final pr = Map<String, dynamic>.from((_r['progreso'] as Map?) ?? {});
    final total = ((pr['total'] ?? 0) as num).toInt();
    final aprob = ((pr['aprobadas'] ?? 0) as num).toInt();
    final frac = total > 0 ? (aprob / total).clamp(0.0, 1.0) : 0.0;
    final hechos = ((_r['hechos'] ?? 0) as num).toInt();
    final nh = _hitos().length;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF8E1621), cessumRed]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${al['nombre'] ?? ''}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
        Text('${al['programa'] ?? ''}${'${al['generacion'] ?? ''}'.isNotEmpty ? ' · ${al['generacion']}' : ''}',
            style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(total > 0 ? '$aprob de $total materias' : 'Plan de estudios',
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: frac,
                  minHeight: 9,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation(Color(0xFFE8C77A)),
                ),
              ),
            ]),
          ),
          const SizedBox(width: 14),
          Text('${pr['porcentaje'] ?? 0}%', style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 14, runSpacing: 4, children: [
          if (pr['promedio'] != null && '${pr['promedio']}' != '0')
            Text('Promedio ${pr['promedio']}', style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
          if ('${pr['egresoEstimado'] ?? ''}'.isNotEmpty && aprob < total)
            Text('Egreso estimado: ${pr['egresoEstimado']}',
                style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
          Text('$hechos de $nh etapas', style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ]),
      ]),
    );
  }

  Widget _tarjetaAhora(Map<String, dynamic> a) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cessumGold.withValues(alpha: 0.55), width: 1.4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.flag, color: cessumGold),
          SizedBox(width: 8),
          Text('Lo más importante ahora', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: cessumGold)),
        ]),
        const SizedBox(height: 6),
        Text('${a['texto'] ?? ''}', style: const TextStyle(fontSize: 13.5, height: 1.4)),
        if (_textoIr.containsKey('${a['ir']}')) ...[
          const SizedBox(height: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            onPressed: () => _ir('${a['ir']}'),
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: Text(_textoIr['${a['ir']}']!),
          ),
        ],
      ]),
    );
  }

  Widget _tarjetaCoach() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cessumMuted(context).withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.auto_awesome, color: cessumRed),
          SizedBox(width: 8),
          Text('Tu coach', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 8),
        if (_coachCargando)
          const Row(children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: cessumRed)),
            SizedBox(width: 10),
            Text('Preparando tu plan…', style: TextStyle(fontSize: 13)),
          ])
        else if (_coachError.isNotEmpty)
          Row(children: [
            Expanded(child: Text(_coachError, style: TextStyle(fontSize: 12.5, color: cessumMuted(context)))),
            TextButton(onPressed: _cargarCoach, child: const Text('Reintentar')),
          ])
        else
          Text(_coach, style: const TextStyle(fontSize: 13.5, height: 1.5)),
        const SizedBox(height: 12),
        TextField(
          controller: _pregunta,
          minLines: 1,
          maxLines: 3,
          maxLength: 500,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _preguntar(),
          decoration: InputDecoration(
            isDense: true,
            border: const OutlineInputBorder(),
            counterText: '',
            hintText: 'Pregúntale sobre tu ruta: ¿cuándo termino?, ¿cómo me titulo?…',
            suffixIcon: _preguntando
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: cessumRed)),
                  )
                : IconButton(icon: const Icon(Icons.send, color: cessumRed), onPressed: _preguntar),
          ),
        ),
        if (_respuesta.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: cessumRed.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10)),
            child: Text(_respuesta, style: const TextStyle(fontSize: 13.5, height: 1.5)),
          ),
        ],
        const SizedBox(height: 6),
        Text('Responde con los datos de tu ruta. Para casos particulares, escribe a contacto@cessum.mx.',
            style: TextStyle(fontSize: 11, color: cessumMuted(context))),
      ]),
    );
  }

  Widget _hito(Map<String, dynamic> h, bool ultimo) {
    final est = '${h['estado']}';
    final Color c = est == 'hecho'
        ? _verde
        : est == 'actual'
            ? cessumRed
            : est == 'bloqueado'
                ? Colors.grey
                : cessumGold;
    final IconData ic = est == 'hecho'
        ? Icons.check_circle
        : est == 'actual'
            ? Icons.radio_button_checked
            : est == 'bloqueado'
                ? Icons.lock_outline
                : Icons.radio_button_unchecked;
    final materias = ((h['materias'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final pagos = ((h['pagos'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final opciones = ((h['opciones'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final faltan = ((h['faltan'] as List?) ?? []).map((e) => '$e').toList();
    final hacer = '${h['hacer'] ?? ''}';
    final ir = '${h['ir'] ?? ''}';
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 34,
          child: Column(children: [
            Icon(ic, color: c, size: 26),
            if (!ultimo) Expanded(child: Container(width: 2, color: c.withValues(alpha: 0.35))),
          ]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.withValues(alpha: est == 'actual' ? 0.7 : 0.3), width: est == 'actual' ? 1.6 : 1),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text('${h['titulo']}',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: est == 'bloqueado' ? Colors.grey : null)),
                ),
                if (est == 'actual')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: cessumRed.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                    child: const Text('Vas aquí', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: cessumRed)),
                  ),
              ]),
              const SizedBox(height: 4),
              Text('${h['detalle'] ?? ''}',
                  style: TextStyle(fontSize: 12.8, height: 1.4, color: est == 'bloqueado' ? Colors.grey : null)),
              for (final m in materias)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('• ${m['materia']} (${m['calificacion']}): ${m['como']}',
                      style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          fontWeight: m['urgente'] == true ? FontWeight.w700 : FontWeight.w400,
                          color: m['urgente'] == true ? cessumRed : null)),
                ),
              for (final p in pagos)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                      '• ${p['concepto']}${_pesos(p['monto']).isNotEmpty ? ' · ${_pesos(p['monto'])}' : ''}'
                      '${'${p['fecha'] ?? ''}'.isNotEmpty ? ' · límite ${p['fecha']}' : ''}'
                      '${p['estatus'] == 'Vencido' ? ' · VENCIDO' : ''}',
                      style: TextStyle(fontSize: 12.5, height: 1.35, color: p['estatus'] == 'Vencido' ? cessumRed : null)),
                ),
              for (final o in opciones)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                      '• ${o['opcion']}${_pesos(o['monto']).isNotEmpty ? ': ${_pesos(o['monto'])}' : ''}'
                      '${o['disponible'] == false ? ' — no disponible${'${o['motivo'] ?? ''}'.isNotEmpty ? ' (${o['motivo']})' : ''}' : ''}',
                      style: TextStyle(fontSize: 12.5, height: 1.35, color: o['disponible'] == false ? Colors.grey : null)),
                ),
              if (faltan.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Falta subir: ${faltan.join(', ')}',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: cessumRed)),
                ),
              if (hacer.isNotEmpty && est != 'hecho' && est != 'bloqueado')
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(hacer, style: const TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic, height: 1.35)),
                ),
              if (est != 'bloqueado' && est != 'hecho' && _textoIr.containsKey(ir))
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: cessumRed, padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                    onPressed: () => _ir(ir),
                    icon: const Icon(Icons.arrow_forward, size: 16),
                    label: Text(_textoIr[ir]!),
                  ),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}
