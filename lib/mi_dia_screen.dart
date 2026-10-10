// mi_dia_screen.dart · CESSUM · (24-sep-2026)
//
// MI DÍA (alumno) · fase 2 de los centros inteligentes.
// Reúne lo que hoy está repartido en cinco pantallas —clases de hoy, tareas
// por entregar, pagos, pendientes, avisos y eventos— y lo ordena por
// urgencia: primero lo de hoy y lo vencido, luego lo de la semana, al final
// lo informativo. El Asistente del alumno entra desde aquí con su perfil.
// Base: GET mi_dia (candado de dueño por matrícula).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'asistente_alumno_screen.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'cessum_ui.dart';
import 'constants.dart';
import 'helpers.dart';
import 'mi_pago_screen.dart';
import 'mis_clases_screen.dart';
import 'mis_pendientes_screen.dart';
import 'student_autolink.dart';
import 'student_profile.dart';
import 'tareas_alumno_screen.dart';

class MiDiaScreen extends StatefulWidget {
  const MiDiaScreen({super.key});

  @override
  State<MiDiaScreen> createState() => _MiDiaScreenState();
}

class _MiDiaScreenState extends State<MiDiaScreen> {
  static const Color _verde = Color(0xFF1E8E3E);

  bool _cargando = true;
  String _error = '';
  Map<String, dynamic>? _d;
  StudentProfile? _perfil;

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
      _perfil = await StudentAutoLink.sincronizarPerfilGuardado();
      final mat = _perfil?.matricula ?? '';
      if (mat.isEmpty) throw Exception('Tu perfil no tiene matrícula todavía. Complétalo para ver tu día.');
      final r = await http
          .get(Uri.parse(guardianUrl).replace(queryParameters: {'accion': 'mi_dia', 'matricula': mat}))
          .timeout(const Duration(seconds: 120));
      final d = jsonDecode(r.body) as Map<String, dynamic>;
      if (d['ok'] != true) throw Exception(d['error'] ?? 'No se pudo armar tu día.');
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
            ? 'No se pudo cargar. Revisa tu conexión e intenta de nuevo.'
            : m;
      });
    }
  }

  void _ir(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));

  Color _color(String tipo, int urgencia) {
    if (urgencia >= 3) return cessumRed;
    if (urgencia == 2) return cessumGold;
    if (tipo == 'evento') return const Color(0xFF1F5B9C);
    return cessumMuted(context);
  }

  IconData _icono(String tipo) {
    switch (tipo) {
      case 'clase':
        return Icons.videocam_outlined;
      case 'tarea':
        return Icons.assignment_outlined;
      case 'pago':
        return Icons.payments_outlined;
      case 'pendiente':
        return Icons.flag_outlined;
      case 'aviso':
        return Icons.campaign_outlined;
      case 'evento':
        return Icons.event_outlined;
    }
    return Icons.circle_outlined;
  }

  void _abrirItem(Map<String, dynamic> it) {
    final enlace = '${it['enlace'] ?? ''}'.trim();
    if (enlace.isNotEmpty && enlace != 'null') {
      Helpers.abrirUrlExterna(enlace, context);
      return;
    }
    switch ('${it['tipo']}') {
      case 'clase':
        _ir(const MisClasesScreen());
        break;
      case 'tarea':
        if (_perfil != null) _ir(TareasAlumnoScreen(perfil: _perfil!));
        break;
      case 'pago':
        _ir(const MiPagoScreen());
        break;
      case 'pendiente':
        _ir(MisPendientesScreen(matricula: _perfil?.matricula ?? '', nombre: _perfil?.nombreCompleto ?? ''));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Mi día', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          IconButton(tooltip: 'Actualizar', onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        onPressed: () => _ir(AsistenteAlumnoScreen(perfil: _perfil)),
        icon: const Icon(Icons.auto_awesome),
        label: const Text('Pregúntale al Asistente'),
      ),
      body: _cargando
          ? const CessumSkeletonList()
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.wb_sunny_outlined, size: 44, color: cessumFaint(context)),
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
    final items = ((d['items'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final urgentes = (d['urgentes'] as num?)?.toInt() ?? 0;
    final hoy = items.where((i) => (i['urgencia'] as num? ?? 0) >= 3).toList();
    final semana = items.where((i) => (i['urgencia'] as num? ?? 0) == 2).toList();
    final info = items.where((i) => (i['urgencia'] as num? ?? 0) <= 1).toList();
    final nombre = (_perfil?.nombreCompleto ?? '').trim().split(' ').first;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [cessumRed, Color(0xFF8E1622)]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${d['saludo'] ?? 'Hola'}${nombre.isNotEmpty ? ', $nombre' : ''}',
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 4),
            Text(
              urgentes == 0 ? 'Nada urgente para hoy' : (urgentes == 1 ? 'Tienes 1 cosa para hoy' : 'Tienes $urgentes cosas para hoy'),
              style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text('Actualizado ${d['generado'] ?? ''}', style: const TextStyle(color: Colors.white60, fontSize: 11.5)),
          ]),
        ),
        const SizedBox(height: 16),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Column(children: [
              Icon(Icons.check_circle_outline, size: 48, color: _verde),
              const SizedBox(height: 8),
              Text('No tienes pendientes registrados. Buen día.', style: TextStyle(color: cessumMuted(context))),
            ]),
          ),
        if (hoy.isNotEmpty) ...[_seccion('HOY'), for (final it in hoy) _fila(it)],
        if (semana.isNotEmpty) ...[const SizedBox(height: 8), _seccion('ESTA SEMANA'), for (final it in semana) _fila(it)],
        if (info.isNotEmpty) ...[const SizedBox(height: 8), _seccion('PARA QUE LO TENGAS PRESENTE'), for (final it in info) _fila(it)],
      ],
    );
  }

  Widget _seccion(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.5, color: cessumMuted(context))),
      );

  Widget _fila(Map<String, dynamic> it) {
    final tipo = '${it['tipo'] ?? ''}';
    final u = (it['urgencia'] as num? ?? 0).toInt();
    final c = _color(tipo, u);
    final tieneAccion = '${it['enlace'] ?? ''}'.trim().isNotEmpty || ['clase', 'tarea', 'pago', 'pendiente'].contains(tipo);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: c.withValues(alpha: 0.4))),
      child: ListTile(
        onTap: tieneAccion ? () => _abrirItem(it) : null,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
          child: Icon(_icono(tipo), color: c, size: 20),
        ),
        title: Text('${it['titulo'] ?? ''}', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: cessumInk(context))),
        subtitle: '${it['detalle'] ?? ''}'.isEmpty
            ? null
            : Text('${it['detalle']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cessumMuted(context))),
        trailing: tieneAccion ? Icon(Icons.chevron_right, color: cessumFaint(context)) : null,
      ),
    );
  }
}
