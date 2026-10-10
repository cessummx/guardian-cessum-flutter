import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'helpers.dart';
import 'avance_captura_screen.dart';
import 'tramites_lista_screen.dart';
import 'riesgo_screen.dart';

/// Pendientes del día: resumen accionable para la Vicerrectoría — grupos sin
/// captura completa, trámites por atender y alumnos en riesgo alto.
class PendientesDiaScreen extends StatefulWidget {
  const PendientesDiaScreen({super.key});

  @override
  State<PendientesDiaScreen> createState() => _PendientesDiaScreenState();
}

class _PendientesDiaScreenState extends State<PendientesDiaScreen> {
  static const Color _verde = Color(0xFF1E8E3E);

  bool _cargando = true;
  String? _error;
  Map<String, dynamic> _data = {};
  DateTime? _ultimaCarga;

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
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=pendientes_dia'))
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'Error');
      if (!mounted) return;
      setState(() {
        _data = data;
        _cargando = false;
        _ultimaCarga = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar los pendientes.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final grupos = (_data['gruposPendientes'] ?? 0) as int;
    final riesgo = (_data['alumnosRiesgo'] ?? 0) as int;
    final tramites = (_data['tramitesPendientes'] ?? 0) as int;
    final porVencer = (_data['tramitesPorVencer'] ?? 0) as int;
    final total = (_data['total'] ?? 0) as int;
    final vencidos = (_data['tramitesVencidos'] ?? 0) as int;
    final urgentes = ((_data['urgentes'] as List?) ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Pendientes del día',
            style: TextStyle(fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
              onPressed: (_cargando || _data.isEmpty) ? null : _copiarResumen,
              icon: const Icon(Icons.copy_all),
              tooltip: 'Copiar resumen del día'),
          IconButton(
              onPressed: _cargando ? null : _cargar,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      TextButton(
                          onPressed: _cargar,
                          child: const Text('Reintentar')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  color: cessumRed,
                  onRefresh: _cargar,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      _resumen(total),
                      if (_ultimaCarga != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8, left: 4),
                          child: Text(
                            Helpers.haceTexto(_ultimaCarga),
                            style: TextStyle(
                                fontSize: 11.5, color: cessumFaint(context)),
                          ),
                        ),
                      const SizedBox(height: 16),
                      // (3-sep) LO QUE TIENE RELOJ, PRIMERO. Antes la pantalla
                      // decía cuántos trámites había pendientes, y con un
                      // número no se sabe a cuál entrar: el que vence hoy se
                      // veía igual que el que acaba de llegar. Ahora encabezan
                      // la pantalla, ordenados por el tiempo que les queda.
                      if (urgentes.isNotEmpty) ...[
                        _bloqueReloj(urgentes, vencidos),
                        const SizedBox(height: 16),
                      ],
                      _tarjeta(
                        'Grupos sin captura completa',
                        grupos,
                        'Materias con calificaciones parciales o sin iniciar.',
                        Icons.fact_check,
                        'Toca para abrir Avance de captura.',
                        onTap: () => _abrir(const AvanceCapturaScreen()),
                      ),
                      _tarjeta(
                        'Trámites por atender',
                        tramites,
                        porVencer > 0
                            ? '$porVencer llevan más de 48 h sin resolverse.'
                            : 'Solicitudes pendientes de resolución.',
                        Icons.assignment_late,
                        'Toca para abrir la lista de trámites.',
                        alerta: porVencer > 0,
                        onTap: () => _abrir(const TramitesListaScreen()),
                      ),
                      _tarjeta(
                        'Alumnos en riesgo alto',
                        riesgo,
                        'Alumnos en nivel rojo (inactividad o reprobación).',
                        Icons.warning_amber,
                        'Toca para abrir Riesgo académico.',
                        onTap: () => _abrir(const RiesgoScreen()),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _resumen(int total) {
    final ok = total == 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: ok
              ? [const Color(0xFF137333), _verde]
              : [const Color(0xFF7A1420), cessumRed],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.notifications_active,
              color: Colors.white, size: 38),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ok ? '¡Todo al día!' : '$total pendiente(s) por atender',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  ok
                      ? 'No hay acciones urgentes en este momento.'
                      : (_venc > 0
                          ? '$_venc trámite(s) YA VENCIERON su plazo de 72 h '
                              'hábiles. Eso es lo primero.'
                          : 'Revisa los puntos de abajo y atiende lo más urgente.'),
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int get _venc => (_data['tramitesVencidos'] ?? 0) as int;

  /// Cuánto le queda a un trámite, en palabras. Negativo = ya venció.
  String _restanteTxt(int? min) {
    if (min == null) return 'sin fecha';
    final neg = min < 0;
    final m = min.abs();
    final d = m ~/ 1440;
    final h = (m % 1440) ~/ 60;
    final mm = m % 60;
    final txt = d > 0 ? '${d}d ${h}h' : (h > 0 ? '${h}h ${mm}m' : '${mm}m');
    return neg ? 'vencido hace $txt' : 'quedan $txt';
  }

  /// Rojo si ya venció o le quedan menos de 8 horas; ámbar si menos de un
  /// día; verde si va con holgura.
  Color _colorReloj(int? min) {
    if (min == null) return Colors.grey;
    if (min < 480) return const Color(0xFFC62828);
    if (min < 1440) return cessumGold;
    return _verde;
  }

  /* (3-sep) Los trámites con cuenta regresiva, arriba de todo. El plazo son
     72 horas HÁBILES desde que el alumno lo pidió: sábado y domingo no
     cuentan, por eso el número no coincide con el reloj de pared. */
  Widget _bloqueReloj(List<Map<String, dynamic>> urgentes, int vencidos) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: (vencidos > 0 ? cessumRed : cessumGold)
                .withValues(alpha: 0.45),
            width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timer_outlined,
                  size: 20, color: vencidos > 0 ? cessumRed : cessumGold),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Con cuenta regresiva',
                    style: TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w900)),
              ),
              if (vencidos > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                      color: cessumRed,
                      borderRadius: BorderRadius.circular(20)),
                  child: Text('$vencidos vencido(s)',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
              'Plazo de 72 horas hábiles desde que el alumno lo solicitó. '
              'Ordenados por el tiempo que les queda.',
              style: TextStyle(fontSize: 11.5, color: cessumMuted(context))),
          const SizedBox(height: 10),
          for (final u in urgentes) _filaReloj(u),
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _abrir(const TramitesListaScreen()),
              child: const Text('Abrir la lista de trámites'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filaReloj(Map<String, dynamic> u) {
    final min = u['restanMin'] is num ? (u['restanMin'] as num).toInt() : null;
    final col = _colorReloj(min);
    final venc = min != null && min < 0;
    return InkWell(
      onTap: () => _abrir(const TramitesListaScreen()),
      child: Container(
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: venc
              ? const Color(0xFFC62828).withValues(alpha: 0.06)
              : cessumGold.withValues(alpha: 0.06), // (24-sep) modo oscuro
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: col.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 5,
              height: 38,
              decoration: BoxDecoration(
                  color: col, borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${u['tipo']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                      [
                        '${u['alumno']}',
                        if ('${u['matricula'] ?? ''}'.isNotEmpty)
                          '${u['matricula']}',
                      ].where((e) => e.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11, color: cessumMuted(context))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_restanteTxt(min),
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: col)),
                const SizedBox(height: 2),
                Text('desde ${u['desde']}',
                    style:
                        const TextStyle(fontSize: 10, color: Colors.black38)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _abrir(Widget pantalla) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla))
        .then((_) => _cargar());
  }

  /// Copia un resumen de texto de los pendientes, para enviarlo a coordinación.
  void _copiarResumen() {
    if (_data.isEmpty) return;
    final grupos = (_data['gruposPendientes'] ?? 0) as int;
    final riesgo = (_data['alumnosRiesgo'] ?? 0) as int;
    final tramites = (_data['tramitesPendientes'] ?? 0) as int;
    final porVencer = (_data['tramitesPorVencer'] ?? 0) as int;
    final total = (_data['total'] ?? 0) as int;
    final hoy = DateTime.now();
    final fecha = '${hoy.day.toString().padLeft(2, '0')}/'
        '${hoy.month.toString().padLeft(2, '0')}/${hoy.year}';
    final b = StringBuffer()
      ..writeln('CESSUM — Pendientes del día ($fecha)')
      ..writeln('Total por atender: $total')
      ..writeln('')
      ..writeln('• Grupos sin captura completa: $grupos')
      ..writeln('• Trámites por atender: $tramites'
          '${porVencer > 0 ? ' ($porVencer con +48 h)' : ''}'
          '${_venc > 0 ? ' — $_venc YA VENCIDOS' : ''}')
      ..writeln('• Alumnos en riesgo alto: $riesgo');
    Helpers.copiarAlPortapapeles(context, b.toString(), 'Pendientes del día');
  }

  Widget _tarjeta(String titulo, int n, String desc, IconData icono,
      String accion,
      {bool alerta = false, VoidCallback? onTap}) {
    final activo = n > 0;
    final color = activo ? (alerta ? cessumRed : cessumGold) : _verde;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: color, width: 5)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icono, color: color, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(titulo,
                                style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700)),
                          ),
                          Text('$n',
                              style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: color)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(desc,
                          style: TextStyle(
                              fontSize: 12, color: cessumMuted(context))),
                      if (activo) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(accion,
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: color)),
                            const SizedBox(width: 4),
                            Icon(Icons.chevron_right, size: 15, color: color),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
