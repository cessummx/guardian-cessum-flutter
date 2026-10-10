import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'captura_calificaciones_screen.dart' show guardianUrl;
import 'constants.dart';
import 'cessum_ui.dart';
import 'auth/session_store.dart';

/// (ADMIN) Genera un libro de Excel con las hojas clave (calificaciones,
/// asignaciones, alumnos, contratos, etc.) y lo ofrece para descargar.
class RespaldoExcelScreen extends StatefulWidget {
  const RespaldoExcelScreen({super.key});

  @override
  State<RespaldoExcelScreen> createState() => _RespaldoExcelScreenState();
}

class _RespaldoExcelScreenState extends State<RespaldoExcelScreen> {
  static const Color _verde = Color(0xFF1E8E3E);

  bool _generando = false;
  String? _url;
  String? _fecha;
  List<String> _hojas = [];
  String? _error;

  Future<void> _generar() async {
    setState(() {
      _generando = true;
      _error = null;
      _url = null;
      _hojas = [];
    });
    try {
      final correo = (await SessionStore.validEmail()) ?? '';
      final body = jsonEncode({
        'accion': 'exportar_respaldo_excel',
        'actor': correo,
      });
      final resp = await http
          .post(Uri.parse(guardianUrl),
              headers: {'Content-Type': 'text/plain;charset=utf-8'}, body: body)
          .timeout(const Duration(seconds: 120));
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (!mounted) return;
      if (data['ok'] == true) {
        setState(() {
          _url = (data['url'] ?? '').toString();
          _fecha = (data['fecha'] ?? '').toString();
          _hojas = (data['hojas'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList();
        });
      } else {
        setState(() => _error =
            (data['error'] ?? 'No se pudo generar el respaldo.').toString());
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Error de conexión al generar el respaldo.');
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  Future<void> _descargar() async {
    if (_url == null) return;
    try {
      await launchUrl(Uri.parse(_url!),
          mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir la descarga.')),
        );
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
        title: const Text('Respaldo en Excel'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cessumGold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cessumGold.withValues(alpha: 0.30)),
            ),
            child: Row(
              children: [
                Icon(Icons.backup_outlined, color: cessumGold, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Genera un archivo de Excel con las hojas clave para guardarlo '
                    'en tu equipo. Útil antes de un cambio grande o un corte de período.',
                    style: CessumType.body(13, color: cessumInk(context)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: cessumRed,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: _generando ? null : _generar,
            icon: _generando
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.cloud_download_outlined),
            label: Text(_generando ? 'Generando…' : 'Generar respaldo en Excel'),
          ),
          if (_generando) ...[
            const SizedBox(height: 10),
            Text('Esto puede tardar unos segundos.',
                style: CessumType.label(12, color: cessumMuted(context))),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cessumRed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cessumRed.withValues(alpha: 0.30)),
              ),
              child: Text(_error!,
                  style: CessumType.body(13, color: cessumRed)),
            ),
          ],
          if (_url != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _verde.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _verde.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle, color: _verde, size: 24),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Respaldo listo${_fecha != null ? ' · $_fecha' : ''}',
                            style: CessumType.heading(15,
                                color: cessumInk(context))),
                      ),
                    ],
                  ),
                  if (_hojas.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('Incluye:',
                        style: CessumType.label(12, color: cessumMuted(context))),
                    const SizedBox(height: 4),
                    for (final h in _hojas)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Row(
                          children: [
                            Icon(Icons.table_chart_outlined,
                                size: 15, color: cessumMuted(context)),
                            const SizedBox(width: 6),
                            Text(h,
                                style: CessumType.body(
                                    12, color: cessumInk(context))),
                          ],
                        ),
                      ),
                  ],
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: _verde),
                    onPressed: _descargar,
                    icon: const Icon(Icons.download),
                    label: const Text('Descargar Excel'),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Si no inicia la descarga, asegúrate de tener la sesión de '
                    'Google de CESSUM abierta en el navegador.',
                    style: CessumType.label(11, color: cessumFaint(context)),
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
