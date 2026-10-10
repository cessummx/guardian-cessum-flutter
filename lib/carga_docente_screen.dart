import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';

/// (ADMIN) Carga académica por docente: cuántas materias/grupos trae cada uno y
/// quiénes están sobrecargados (por encima del umbral), para equilibrar.
class CargaDocenteScreen extends StatefulWidget {
  const CargaDocenteScreen({super.key});

  @override
  State<CargaDocenteScreen> createState() => _CargaDocenteScreenState();
}

class _CargaDocenteScreenState extends State<CargaDocenteScreen> {
  static const Color _verde = Color(0xFF1E8E3E);

  List<Map<String, dynamic>> _docentes = [];
  int _umbral = 5;
  int _totalSobrecarga = 0;
  bool _cargando = true;
  bool _soloSobrecarga = false;
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
      final correo = (await SessionStore.realEmail()) ?? '';
      final uri = Uri.parse(guardianUrl).replace(queryParameters: {
        'accion': 'carga_docente',
        'correo': correo,
        'umbral': '$_umbral',
      });
      final resp = await http.get(uri).timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) throw Exception(data['error'] ?? 'No autorizado');
      final lista = (data['docentes'] as List<dynamic>? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        _docentes = lista;
        _umbral = (data['umbral'] ?? 5) as int;
        _totalSobrecarga = (data['totalSobrecarga'] ?? 0) as int;
        _cargando = false;
      });
    } catch (_) {
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
      final correo = (await SessionStore.realEmail()) ?? '';
      final body = jsonEncode({
        'accion': 'exportar_reportes_excel',
        'actor': correo,
        'umbral': '$_umbral',
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
        title: const Text('Carga docente'),
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

    final maxMat = _docentes.isEmpty
        ? 1
        : _docentes
            .map((d) => (d['materias'] ?? 0) as int)
            .reduce((a, b) => a > b ? a : b);
    final visibles = _soloSobrecarga
        ? _docentes.where((d) => d['sobrecarga'] == true).toList()
        : _docentes;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _resumen(),
        const SizedBox(height: 12),
        _selectorUmbral(),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text('Mostrar solo sobrecargados',
                  style: CessumType.body(13, color: cessumInk(context))),
            ),
            Switch(
              value: _soloSobrecarga,
              activeColor: cessumRed,
              onChanged: (v) => setState(() => _soloSobrecarga = v),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (visibles.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 50),
            child: CessumEmptyState(
              title: 'Sin sobrecarga',
              subtitle: 'Ningún docente supera el umbral establecido.',
              icon: Icons.balance,
            ),
          )
        else
          for (final d in visibles) _barraDocente(d, maxMat),
      ],
    );
  }

  Widget _resumen() {
    final hay = _totalSobrecarga > 0;
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
          Icon(hay ? Icons.warning_amber_rounded : Icons.balance,
              color: color, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    hay
                        ? '$_totalSobrecarga docente(s) sobrecargado(s)'
                        : 'Carga equilibrada',
                    style: CessumType.heading(16, color: cessumInk(context))),
                const SizedBox(height: 2),
                Text('${_docentes.length} docentes · umbral $_umbral materias',
                    style: CessumType.body(13, color: cessumMuted(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectorUmbral() {
    return Row(
      children: [
        Text('Umbral de sobrecarga:',
            style: CessumType.body(13, color: cessumInk(context))),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          color: cessumRed,
          onPressed: _umbral > 1
              ? () {
                  setState(() => _umbral--);
                  _cargar();
                }
              : null,
        ),
        Text('$_umbral',
            style: CessumType.heading(18, color: cessumInk(context))),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          color: cessumRed,
          onPressed: () {
            setState(() => _umbral++);
            _cargar();
          },
        ),
      ],
    );
  }

  Widget _barraDocente(Map<String, dynamic> d, int maxMat) {
    final isDark = cessumIsDark(context);
    final docente = (d['docente'] ?? '').toString();
    final materias = (d['materias'] ?? 0) as int;
    final grupos = (d['grupos'] ?? 0) as int;
    final sobre = d['sobrecarga'] == true;
    final frac = maxMat > 0 ? materias / maxMat : 0.0;
    final color = sobre ? cessumRed : _verde;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF211F1D) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(docente,
                    style: CessumType.heading(14, color: cessumInk(context))),
              ),
              if (sobre)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: cessumRed.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('Sobrecarga',
                      style: CessumType.label(10, color: cessumRed)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: frac.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: color.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 6),
          Text('$materias materias · $grupos grupos',
              style: CessumType.body(12, color: cessumMuted(context))),
        ],
      ),
    );
  }
}
