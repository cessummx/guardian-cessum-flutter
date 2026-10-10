// ADMIN · SIGA: bitácora de exportaciones. Lista cada paquete generado (fecha,
// quién, ciclo/carga, registros/errores) con acceso a su carpeta de Drive.
// Da control institucional de qué se ha subido a la autoridad y cuándo.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'constants.dart';
import 'cessum_ui.dart';
import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'auth/session_store.dart';   // (23-sep) SIGA cerrado

class SigaBitacoraScreen extends StatefulWidget {
  const SigaBitacoraScreen({super.key});

  @override
  State<SigaBitacoraScreen> createState() => _SigaBitacoraScreenState();
}

class _SigaBitacoraScreenState extends State<SigaBitacoraScreen> {
  List<Map<String, dynamic>> _registros = [];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final resp = await http
          .get(Uri.parse('$guardianUrl?accion=siga_bitacora_listar'
              '&actor=${Uri.encodeQueryComponent(((await SessionStore.realEmail()) ?? '').trim().toLowerCase())}'))
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _registros = ((data['registros'] as List?) ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _cargando = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cessumBg(context),
      appBar: AppBar(
        backgroundColor: cessumRed,
        foregroundColor: Colors.white,
        title: const Text('Bitácora de exportaciones SIGA'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _cargar),
        ],
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator(color: cessumRed))
          : _registros.isEmpty
              ? _vacio()
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Historial de paquetes generados. Cada uno queda en Drive '
                      'con su ciclo y fecha.',
                      style: TextStyle(
                          fontSize: 12.5, color: cessumMuted(context)),
                    ),
                    const SizedBox(height: 12),
                    ..._registros.map(_tarjeta),
                    const SizedBox(height: 24),
                  ],
                ),
    );
  }

  Widget _vacio() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 48, color: cessumMuted(context)),
            const SizedBox(height: 12),
            Text('Aún no se ha exportado ningún paquete.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cessumMuted(context))),
            const SizedBox(height: 4),
            Text(
              'Cuando generes un paquete completo, aparecerá aquí.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: cessumMuted(context)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tarjeta(Map<String, dynamic> r) {
    final ciclo = (r['ciclo'] ?? '').toString();
    final carga = (r['carga'] ?? '').toString();
    final errores = r['errores'] ?? 0;
    final url = (r['carpetaUrl'] ?? '').toString();
    final periodo = ciclo == 'todos' || ciclo.isEmpty
        ? 'Todo el histórico'
        : '$ciclo${carga.isNotEmpty ? ' · carga $carga' : ''}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cessumMuted(context).withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.folder_zip_outlined,
                  color: cessumRed, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(periodo,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800)),
              ),
              Text('${r['formatos'] ?? ''}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: cessumMuted(context))),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.event, size: 13, color: cessumMuted(context)),
              const SizedBox(width: 4),
              Text('${r['fecha'] ?? ''}',
                  style:
                      TextStyle(fontSize: 12, color: cessumMuted(context))),
              const SizedBox(width: 12),
              Icon(Icons.person_outline,
                  size: 13, color: cessumMuted(context)),
              const SizedBox(width: 4),
              Expanded(
                child: Text('${r['actor'] ?? ''}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, color: cessumMuted(context))),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _pill('${r['registros'] ?? 0} registros',
                  const Color(0xFF1E8E3E)),
              const SizedBox(width: 6),
              if (errores != 0)
                _pill('$errores con error', const Color(0xFFB08D57)),
              const Spacer(),
              if (url.isNotEmpty)
                TextButton.icon(
                  onPressed: () => launchUrl(Uri.parse(url),
                      mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.folder_open, size: 16),
                  label: const Text('Abrir', style: TextStyle(fontSize: 12.5)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(String txt, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(txt,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: color)),
    );
  }
}
