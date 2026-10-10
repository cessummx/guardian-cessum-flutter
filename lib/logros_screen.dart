import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'constants.dart';
import 'cessum_ui.dart';
import 'cessum_vacio.dart';
import 'cessum_skeleton.dart';
import 'auth/session_store.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;

/// Logros y gamificación del alumno: nivel, puntos, progreso e
/// insignias, calculados por el Guardián a partir de sus calificaciones.
class LogrosScreen extends StatefulWidget {
  const LogrosScreen({super.key});

  @override
  State<LogrosScreen> createState() => _LogrosScreenState();
}

class _LogrosScreenState extends State<LogrosScreen> {
  bool _cargando = true;
  String _error = '';
  Map<String, dynamic> _d = {};

  static const Map<String, IconData> _iconos = {
    'flag': Icons.flag,
    'run': Icons.directions_run,
    'rocket': Icons.rocket_launch,
    'medal': Icons.military_tech,
    'star': Icons.star,
    'shield': Icons.shield,
  };

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (mounted) setState(() { _cargando = true; _error = ''; });
    try {
      final correo = (await SessionStore.validEmail()) ?? '';
      final uri = Uri.parse(
          '$guardianUrl?accion=logros_alumno&correo=${Uri.encodeComponent(correo)}');
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final d = jsonDecode(resp.body) as Map<String, dynamic>;
      if (d['ok'] != true) {
        if (mounted) setState(() { _error = (d['error'] ?? 'No se pudo cargar.').toString(); _cargando = false; });
        return;
      }
      if (mounted) setState(() { _d = d; _cargando = false; });
    } catch (e) {
      if (mounted) setState(() { _error = 'Error de conexión.'; _cargando = false; });
    }
  }

  int _i(dynamic v) => (v is num) ? v.toInt() : 0;
  String _t(dynamic v) => (v ?? 0).toString();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        title: const Text('Mis logros'),
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        actions: [
          IconButton(onPressed: _cargando ? null : _cargar, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _cargando
          ? _skeleton()
          : _error.isNotEmpty
              ? CessumVacio(
                  titulo: 'No pudimos cargar tus logros',
                  mensaje: _error,
                  iconoFallback: Icons.emoji_events,
                  accion: FilledButton.icon(
                    onPressed: _cargar,
                    style: FilledButton.styleFrom(backgroundColor: cessumRed),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  ),
                )
              : _contenido(),
    );
  }

  Widget _skeleton() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const CessumSkeleton(height: 150, radius: 18),
        const SizedBox(height: 16),
        Row(
          children: const [
            Expanded(child: CessumSkeleton(height: 90, radius: 14)),
            SizedBox(width: 10),
            Expanded(child: CessumSkeleton(height: 90, radius: 14)),
            SizedBox(width: 10),
            Expanded(child: CessumSkeleton(height: 90, radius: 14)),
          ],
        ),
        const SizedBox(height: 20),
        const CessumSkeleton(width: 120, height: 16),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.85,
          children: const [
            CessumSkeleton(radius: 14),
            CessumSkeleton(radius: 14),
            CessumSkeleton(radius: 14),
            CessumSkeleton(radius: 14),
            CessumSkeleton(radius: 14),
            CessumSkeleton(radius: 14),
          ],
        ),
      ],
    );
  }

  Widget _contenido() {
    final nivel = _i(_d['nivel']);
    final aprobadas = _i(_d['aprobadas']);
    final meta = _i(_d['materiasParaSiguienteNivel']);
    final frac = (meta > 0) ? (aprobadas / meta).clamp(0.0, 1.0) : 1.0;
    final insignias = (_d['insignias'] is List) ? _d['insignias'] as List : const [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Nivel + puntos
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [cessumRed, Color(0xFF8E1622)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              Text('Nivel $nivel',
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(height: 2),
              Text('${_t(_d['puntos'])} puntos',
                  style: const TextStyle(fontSize: 15, color: Colors.white70)),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: frac,
                  minHeight: 10,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                aprobadas >= meta
                    ? '¡Vas con todo!'
                    : 'Te faltan ${meta - aprobadas} materia(s) para el nivel ${nivel + 1}',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Estadísticas
        Row(
          children: [
            Expanded(child: _stat('Aprobadas', _t(_d['aprobadas']), Icons.check_circle, const Color(0xFF1E8E3E))),
            const SizedBox(width: 10),
            Expanded(child: _stat('Cursadas', _t(_d['cursadas']), Icons.menu_book, cessumGold)),
            const SizedBox(width: 10),
            Expanded(child: _stat('Promedio', _t(_d['promedio']), Icons.trending_up, cessumRed)),
          ],
        ),
        const SizedBox(height: 20),

        Row(
          children: [
            Text('Insignias',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: cessumInk(context))),
            const Spacer(),
            Text('${_t(_d['obtenidas'])}/${_t(_d['totalInsignias'])}',
                style: TextStyle(fontSize: 13, color: cessumMuted(context))),
          ],
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.85,
          children: [
            for (final b in insignias)
              if (b is Map) _insignia(b),
          ],
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _stat(String titulo, String valor, IconData icono, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Icon(icono, color: color, size: 24),
          const SizedBox(height: 6),
          Text(valor, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 2),
          Text(titulo, style: TextStyle(fontSize: 11, color: cessumMuted(context))),
        ],
      ),
    );
  }

  Widget _insignia(Map b) {
    final obtenida = b['obtenida'] == true;
    final icono = _iconos[b['icono']?.toString()] ?? Icons.emoji_events;
    final color = obtenida ? cessumGold : cessumFaint(context);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: obtenida ? cessumGold.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.40)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(obtenida ? icono : Icons.lock_outline, color: color, size: 30),
          const SizedBox(height: 6),
          Text(
            (b['titulo'] ?? '').toString(),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: obtenida ? cessumInk(context) : cessumFaint(context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            (b['desc'] ?? '').toString(),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 9, color: cessumFaint(context)),
          ),
        ],
      ),
    );
  }
}
