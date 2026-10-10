import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';

/// (ADMIN) Muestra qué docentes tienen materias activas SIN contrato generado,
/// para darles seguimiento. Cruza asignaciones activas con los contratos.
class ContratosFaltantesScreen extends StatefulWidget {
  const ContratosFaltantesScreen({super.key});

  @override
  State<ContratosFaltantesScreen> createState() =>
      _ContratosFaltantesScreenState();
}

class _ContratosFaltantesScreenState extends State<ContratosFaltantesScreen> {
  static const Color _verde = Color(0xFF1E8E3E);

  List<Map<String, dynamic>> _docentes = [];
  int _totalFaltan = 0;
  int _profesConFalta = 0;
  bool _cargando = true;
  bool _soloFaltantes = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (mounted) {
      setState(() {
        _cargando = true;
        _error = null;
      });
    }
    try {
      final correo = (await SessionStore.validEmail()) ?? '';
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'contratos_faltantes_admin',
        'correo': correo,
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) {
        throw Exception(data['error'] ?? 'No autorizado');
      }
      final lista = (data['docentes'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _docentes = lista;
        _totalFaltan = (data['totalFaltan'] ?? 0) as int;
        _profesConFalta = (data['profesConFalta'] ?? 0) as int;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _error = 'No se pudo cargar. ¿Tienes permiso de administrador?';
      });
    }
  }

  Future<void> _exportar() async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Generando Excel… puede tardar unos segundos.')));
    }
    try {
      final correo = (await SessionStore.validEmail()) ?? '';
      final body = jsonEncode({
        'accion': 'exportar_reportes_excel',
        'actor': correo,
      });
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'}, body: body)
          .timeout(const Duration(seconds: 90));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      final url = (data['url'] ?? '').toString();
      if (data['ok'] == true && url.isNotEmpty) {
        await launchUrl(Uri.parse(url),
            mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo exportar.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error al exportar a Excel.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Contratos pendientes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Exportar a Excel',
            onPressed: _exportar,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargando ? null : _cargar,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        color: cessumRed,
        child: _cuerpo(),
      ),
    );
  }

  Widget _cuerpo() {
    if (_cargando) {
      return ListView(padding: const EdgeInsets.all(16), children: const [
        SkeletonCard(),
        SizedBox(height: 12),
        SkeletonCard(),
      ]);
    }
    if (_error != null) {
      return ListView(children: [
        const SizedBox(height: 80),
        CessumEmptyState(
          title: 'No se pudo cargar',
          subtitle: _error,
          icon: Icons.lock_outline,
          action: FilledButton.icon(
            onPressed: _cargar,
            style: FilledButton.styleFrom(backgroundColor: cessumRed),
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ),
      ]);
    }

    final visibles = _soloFaltantes
        ? _docentes.where((d) => ((d['faltan'] ?? 0) as int) > 0).toList()
        : _docentes;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _resumen(),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text('Mostrar solo con pendientes',
                  style: CessumType.body(13, color: cessumInk(context))),
            ),
            Switch(
              value: _soloFaltantes,
              activeColor: cessumRed,
              onChanged: (v) => setState(() => _soloFaltantes = v),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (visibles.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 60),
            child: CessumEmptyState(
              title: '¡Todo al día!',
              subtitle: 'No hay materias activas sin contrato.',
              icon: Icons.verified_outlined,
            ),
          )
        else
          for (final d in visibles) _tarjetaDocente(d),
      ],
    );
  }

  Widget _resumen() {
    final hay = _totalFaltan > 0;
    final color = hay ? cessumRed : _verde;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(hay ? Icons.assignment_late_outlined : Icons.verified,
              color: color, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    hay
                        ? '$_totalFaltan materia(s) sin contrato'
                        : 'Sin contratos pendientes',
                    style: CessumType.heading(16, color: cessumInk(context))),
                const SizedBox(height: 2),
                Text('$_profesConFalta docente(s) con pendientes',
                    style: CessumType.body(13, color: cessumMuted(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaDocente(Map<String, dynamic> d) {
    final isDark = cessumIsDark(context);
    final docente = (d['docente'] ?? '').toString();
    final correo = (d['correo'] ?? '').toString();
    final total = (d['total'] ?? 0) as int;
    final conContrato = (d['conContrato'] ?? 0) as int;
    final faltan = (d['faltan'] ?? 0) as int;
    final faltantes = (d['faltantes'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();
    final contratadas = (d['contratadas'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF211F1D) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: faltan > 0
              ? cessumRed.withValues(alpha: 0.30)
              : _verde.withValues(alpha: 0.30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(docente,
                        style: CessumType.heading(14, color: cessumInk(context))),
                    if (correo.isNotEmpty)
                      Text(correo,
                          style: CessumType.label(11, color: cessumMuted(context))),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: (faltan > 0 ? cessumRed : _verde).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('$conContrato/$total',
                    style: CessumType.label(
                        12, color: faltan > 0 ? cessumRed : _verde)),
              ),
            ],
          ),
          if (faltantes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Faltan contrato:',
                style: CessumType.label(11, color: cessumRed)),
            const SizedBox(height: 4),
            for (final m in faltantes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, size: 15, color: cessumRed),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(m,
                          style: CessumType.body(12, color: cessumInk(context))),
                    ),
                  ],
                ),
              ),
          ],
          if (contratadas.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final c in contratadas)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle, size: 15, color: _verde),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${c['materia']}  ·  ${c['estatus']}',
                        style: CessumType.body(12, color: cessumMuted(context)),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
