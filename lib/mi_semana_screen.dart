// mi_semana_screen.dart · CESSUM · (24-sep-2026)
//
// MI SEMANA (docente) · fase 2 de los centros inteligentes.
// Una sola pantalla con lo que hoy está repartido: clases de la semana por
// día, qué falta capturar, entregas por revisar, mensajes sin responder,
// notificaciones y los pendientes del Guardián. Con IA: «Su plan para esta
// semana», en tres pasos con su momento.
// Base: GET mi_semana y mi_semana_ia (candado de dueño por correo).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'cessum_ui.dart';
import 'constants.dart';
import 'helpers.dart';
import 'mensajes_screen.dart';
import 'mi_captura_screen.dart';
import 'mi_horario_docente_screen.dart';
import 'revisiones_screen.dart';
import 'tareas_docente_screen.dart';

class MiSemanaScreen extends StatefulWidget {
  const MiSemanaScreen({super.key});

  @override
  State<MiSemanaScreen> createState() => _MiSemanaScreenState();
}

class _MiSemanaScreenState extends State<MiSemanaScreen> {
  static const Color _verde = Color(0xFF1E8E3E);
  static const _dias = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];

  bool _cargando = true;
  String _error = '';
  Map<String, dynamic>? _d;
  String _correo = '';

  bool _pidiendoIa = false;
  List<Map<String, dynamic>> _pasos = [];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = '';
    });
    try {
      _correo = (await SessionStore.validEmail() ?? '').trim().toLowerCase();
      if (_correo.isEmpty) throw Exception('No hay sesión de docente.');
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'mi_semana', 'correo': _correo}))
          .timeout(const Duration(seconds: 120));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo armar la semana.');
      if (!mounted) return;
      setState(() {
        _d = d;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      final m = '$e'.replaceFirst('Exception: ', '');
      setState(() {
        _cargando = false;
        _error = (m.contains('TimeoutException') || m.contains('ClientException') || m.contains('SocketException'))
            ? 'No se pudo cargar. Revise su conexión e intente de nuevo.'
            : m;
      });
    }
  }

  Future<void> _plan() async {
    setState(() => _pidiendoIa = true);
    try {
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'mi_semana_ia', 'correo': _correo}))
          .timeout(const Duration(seconds: 120));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo generar el plan.');
      if (!mounted) return;
      setState(() => _pasos = ((d['pasos'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList());
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            backgroundColor: cessumRed, content: Text('$e'.replaceFirst('Exception: ', ''))));
      }
    }
    if (mounted) setState(() => _pidiendoIa = false);
  }

  void _ir(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Mi semana', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(
            tooltip: 'Mi plan para esta semana (IA)',
            onPressed: (_cargando || _pidiendoIa) ? null : _plan,
            icon: _pidiendoIa
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.auto_awesome),
          ),
          IconButton(tooltip: 'Actualizar', onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const CessumSkeletonList()
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.cloud_off_outlined, size: 44, color: cessumFaint(context)),
                      const SizedBox(height: 10),
                      Text(_error, textAlign: TextAlign.center, style: TextStyle(color: cessumInk(context))),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: _cargar, child: const Text('Reintentar')),
                    ]),
                  ),
                )
              : RefreshIndicator(color: cessumRed, onRefresh: _cargar, child: _cuerpo()),
    );
  }

  Widget _cuerpo() {
    final d = _d!;
    final semana = Map<String, dynamic>.from((d['semana'] as Map?) ?? {});
    final porDia = Map<String, dynamic>.from((d['porDia'] as Map?) ?? {});
    final capPend = ((d['capturaPendiente'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final porRevisar = (d['porRevisar'] as num?)?.toInt() ?? 0;
    final tareasAbiertas = (d['tareasAbiertas'] as num?)?.toInt() ?? 0;
    final sinLeer = (d['mensajesSinLeer'] as num?)?.toInt() ?? 0;
    final notis = (d['notificaciones'] as num?)?.toInt() ?? 0;
    final clases = ((d['clases'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final pendientes = d['pendientes'] is Map ? Map<String, dynamic>.from(d['pendientes'] as Map) : <String, dynamic>{};
    final hoyNombre = '${semana['hoy'] ?? ''}';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _encabezado(semana, capPend.length, porRevisar, sinLeer),
        if (_pasos.isNotEmpty) ...[const SizedBox(height: 12), _cajaPlan()],
        const SizedBox(height: 16),
        _seccion('LO QUE PIDE SU ATENCIÓN'),
        _accion(Icons.grading_outlined, 'Captura pendiente', capPend.isEmpty ? 'Al día' : '${capPend.length} grupo(s) con calificaciones sin capturar',
            capPend.isEmpty ? _verde : cessumRed, () => _ir(const MiCapturaScreen())),
        _accion(Icons.rate_review_outlined, 'Entregas por revisar', porRevisar == 0 ? 'Nada pendiente' : '$porRevisar trabajo(s) esperan retroalimentación',
            porRevisar == 0 ? _verde : cessumGold, () => _ir(const RevisionesScreen())),
        _accion(Icons.forum_outlined, 'Mensajes sin responder', sinLeer == 0 ? 'Todo respondido' : '$sinLeer mensaje(s) de alumnos',
            sinLeer == 0 ? _verde : cessumGold, () => _ir(const MensajesScreen())),
        _accion(Icons.assignment_outlined, 'Tareas abiertas', '$tareasAbiertas tarea(s) vigente(s)', cessumMuted(context), () => _ir(const TareasDocenteScreen())),
        if (notis > 0)
          _accion(Icons.notifications_active_outlined, 'Notificaciones', '$notis sin leer', cessumGold, null),
        ..._pendientesGuardian(pendientes),
        const SizedBox(height: 16),
        _seccion('CLASES DE ESTA SEMANA'),
        if (clases.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('No tiene grupos asignados en este periodo.', style: TextStyle(color: cessumMuted(context))),
          ),
        for (final dia in _dias)
          if ((porDia[dia] as List?)?.isNotEmpty == true) _dia(dia, dia == hoyNombre, (porDia[dia] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList()),
        if (clases.isNotEmpty && porDia.isEmpty)
          for (final c in clases) _clase(c, false),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _ir(const MiHorarioDocenteScreen()),
            icon: const Icon(Icons.schedule_outlined, size: 16),
            label: const Text('Ver mi horario completo'),
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _encabezado(Map<String, dynamic> semana, int capPend, int porRevisar, int sinLeer) {
    final urgentes = (capPend > 0 ? 1 : 0) + (porRevisar > 0 ? 1 : 0) + (sinLeer > 0 ? 1 : 0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [cessumRed, Color(0xFF8E1622)]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Semana del ${semana['inicio'] ?? ''} al ${semana['fin'] ?? ''}',
            style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
        const SizedBox(height: 4),
        Text(urgentes == 0 ? 'Todo al día. Buena semana.' : (urgentes == 1 ? 'Un frente por atender' : '$urgentes frentes por atender'),
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
        if (_pasos.isEmpty) ...[
          const SizedBox(height: 10),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.white.withValues(alpha: 0.14)),
            onPressed: _pidiendoIa ? null : _plan,
            icon: const Icon(Icons.auto_awesome, size: 16),
            label: Text(_pidiendoIa ? 'Pensando…' : 'Mi plan para esta semana'),
          ),
        ],
      ]),
    );
  }

  Widget _cajaPlan() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cessumGold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cessumGold.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.auto_awesome, size: 16, color: cessumGold),
          const SizedBox(width: 6),
          Text('MI PLAN PARA ESTA SEMANA', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: cessumInk(context))),
          const Spacer(),
          IconButton(
            tooltip: 'Copiar',
            iconSize: 18,
            onPressed: () => Helpers.copiarAlPortapapeles(
                context, _pasos.map((p) => '• ${p['paso']} (${p['cuando']})').join('\n'), 'Plan'),
            icon: const Icon(Icons.copy_outlined),
          ),
        ]),
        for (var i = 0; i < _pasos.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(radius: 11, backgroundColor: cessumRed,
                  child: Text('${i + 1}', style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w800))),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${_pasos[i]['paso'] ?? ''}', style: TextStyle(fontSize: 13.5, height: 1.35, fontWeight: FontWeight.w600, color: cessumInk(context))),
                  if ('${_pasos[i]['cuando'] ?? ''}'.isNotEmpty)
                    Text('${_pasos[i]['cuando']}', style: TextStyle(fontSize: 12, color: cessumMuted(context))),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _seccion(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: cessumMuted(context))),
      );

  Widget _accion(IconData icono, String titulo, String detalle, Color color, VoidCallback? onTap) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: color.withValues(alpha: 0.4))),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: Icon(icono, color: color, size: 20),
        ),
        title: Text(titulo, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: cessumInk(context))),
        subtitle: Text(detalle, style: TextStyle(fontSize: 12, color: cessumMuted(context))),
        trailing: onTap == null ? null : Icon(Icons.chevron_right, color: cessumFaint(context)),
      ),
    );
  }

  /// Pendientes que ya calcula el Guardián para el docente (captura, actas, contrato…).
  List<Widget> _pendientesGuardian(Map<String, dynamic> p) {
    final out = <Widget>[];
    p.forEach((k, v) {
      if (v is List && v.isNotEmpty) {
        out.add(_accion(Icons.flag_outlined, _titulo(k), '${v.length} pendiente(s)', cessumGold, null));
      } else if (v is Map && v.isNotEmpty) {
        final n = (v['total'] ?? v['pendientes'] ?? v['n']);
        if (n is num && n > 0) out.add(_accion(Icons.flag_outlined, _titulo(k), '$n pendiente(s)', cessumGold, null));
      } else if (v is num && v > 0 && k != 'ok') {
        out.add(_accion(Icons.flag_outlined, _titulo(k), '$v pendiente(s)', cessumGold, null));
      }
    });
    return out;
  }

  String _titulo(String k) {
    final s = k.replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m.group(1)!.toLowerCase()}');
    return s.isEmpty ? k : s[0].toUpperCase() + s.substring(1);
  }

  Widget _dia(String dia, bool esHoy, List<Map<String, dynamic>> clases) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(dia[0].toUpperCase() + dia.substring(1),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: esHoy ? cessumRed : cessumInk(context))),
          if (esHoy) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: cessumRed.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
              child: const Text('HOY', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: cessumRed)),
            ),
          ],
        ]),
        const SizedBox(height: 4),
        for (final c in clases) _clase(c, esHoy),
      ]),
    );
  }

  Widget _clase(Map<String, dynamic> c, bool esHoy) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: esHoy ? cessumRed.withValues(alpha: 0.45) : Theme.of(context).dividerColor),
      ),
      child: Row(children: [
        Icon(Icons.class_outlined, size: 18, color: esHoy ? cessumRed : cessumMuted(context)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${c['materia'] ?? ''}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cessumInk(context))),
            Text(
              [
                if ('${c['programa'] ?? ''}'.isNotEmpty) '${c['programa']}',
                if ('${c['generacion'] ?? ''}'.isNotEmpty) '${c['generacion']}',
                if ('${c['grupo'] ?? ''}'.isNotEmpty) 'Grupo ${c['grupo']}',
                if ('${c['hora'] ?? ''}'.isNotEmpty) '${c['hora']}',
              ].join(' · '),
              style: TextStyle(fontSize: 11.5, color: cessumMuted(context)),
            ),
          ]),
        ),
      ]),
    );
  }
}
